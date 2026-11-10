import Darwin
import Foundation

public protocol ProcessSource: Sendable {
    func snapshot() throws -> [ProcessRecord]
    /// Fills the details `snapshot()` skips for non-listening processes (path, argv, cwd).
    func enrich(_ record: ProcessRecord) -> ProcessRecord
}

extension ProcessSource {
    public func enrich(_ record: ProcessRecord) -> ProcessRecord { record }
}

public enum LiveProcessSourceError: Error, Equatable {
    case listPidsFailed(errno: Int32)
}

/// Reads the live process table via libproc and sysctl (no `lsof`).
public struct LiveProcessSource: ProcessSource {
    public init() {}

    public func snapshot() throws -> [ProcessRecord] {
        let myUid = getuid()
        var records: [Int32: ProcessRecord] = [:]
        var listening: [Int32] = []

        for pid in try Self.allPids() {
            guard let info = Self.basicInfo(pid) else { continue }
            var record = ProcessRecord(
                pid: pid, ppid: info.ppid, uid: info.uid, name: info.comm,
                executablePath: nil, arguments: [], cwd: nil, startTime: info.startTime,
                residentBytes: 0, listeningPorts: [])
            if info.uid == myUid {
                record.listeningPorts = Self.listeningPorts(pid)
                if !record.listeningPorts.isEmpty { listening.append(pid) }
            }
            records[pid] = record
        }

        // Enrich listening processes and their ancestors. Other users' processes
        // only get their executable path (proc_pidpath works across users).
        var enriched = Set<Int32>()
        for pid in listening {
            var current: Int32? = pid
            while let p = current, p > 0, !enriched.contains(p), var record = records[p] {
                enriched.insert(p)
                Self.enrich(&record, owned: record.uid == myUid)
                records[p] = record
                current = record.ppid
            }
        }

        return records.keys.sorted().compactMap { records[$0] }
    }

    /// User-owned processes get path, name, argv, cwd and memory; others get the path only.
    public func enrich(_ record: ProcessRecord) -> ProcessRecord {
        var record = record
        Self.enrich(&record, owned: record.uid == getuid())
        return record
    }

    // MARK: - libproc helpers

    private static func allPids() throws -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { throw LiveProcessSourceError.listPidsFailed(errno: errno) }
        // Headroom for processes spawned between the two calls.
        let capacity = Int(needed) / MemoryLayout<Int32>.size + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard written > 0 else { throw LiveProcessSourceError.listPidsFailed(errno: errno) }
        return pids.prefix(Int(written) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    struct BasicInfo: Equatable {
        var ppid: Int32
        var uid: UInt32
        var comm: String
        var startTime: Date
    }

    /// ppid, uid, comm and start time; nil for exited (including zombie) processes.
    /// `PROC_PIDTBSDINFO` fails with EPERM for other
    /// users' processes (e.g. launchd, setuid-root `login`), so fall back to
    /// `sysctl(KERN_PROC_PID)`, which reads the same kernel start-time field.
    static func basicInfo(_ pid: Int32) -> BasicInfo? {
        bsdInfo(pid) ?? kinfoInfo(pid)
    }

    static func bsdInfo(_ pid: Int32) -> BasicInfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != UInt32(SZOMB) else { return nil }
        let comm = string(fromTuple: info.pbi_name).nonEmpty ?? string(fromTuple: info.pbi_comm)
        return BasicInfo(
            ppid: Int32(bitPattern: info.pbi_ppid), uid: info.pbi_uid, comm: comm,
            startTime: startDate(seconds: Int64(info.pbi_start_tvsec),
                                 microseconds: Int64(info.pbi_start_tvusec)))
    }

    static func kinfoInfo(_ pid: Int32) -> BasicInfo? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // A vanished pid returns success with size 0. A zombie has exited: treat it as gone.
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid, info.kp_proc.p_stat != SZOMB else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return BasicInfo(
            ppid: info.kp_eproc.e_ppid, uid: info.kp_eproc.e_ucred.cr_uid,
            comm: string(fromTuple: info.kp_proc.p_comm),
            startTime: startDate(seconds: Int64(start.tv_sec),
                                 microseconds: Int64(start.tv_usec)))
    }

    private static func startDate(seconds: Int64, microseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000)
    }

    private static func listeningPorts(_ pid: Int32) -> [UInt16] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let written = fds.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard written > 0 else { return [] }

        var ports = Set<UInt16>()
        let socketInfoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        for fd in fds.prefix(Int(written) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, socketInfoSize)
                    == socketInfoSize,
                  si.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = si.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN),
                  tcp.tcpsi_ini.insi_vflag & UInt8(INI_IPV4 | INI_IPV6) != 0 else { continue }
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            if port != 0 { ports.insert(port) }
        }
        return ports.sorted()
    }

    private static func enrich(_ record: inout ProcessRecord, owned: Bool) {
        let pid = record.pid
        if let path = executablePath(pid) {
            record.executablePath = path
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty { record.name = base }
        }
        guard owned else { return }
        record.cwd = cwd(pid)
        record.arguments = arguments(pid)
        record.residentBytes = residentBytes(pid)
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return string(fromTuple: info.pvi_cdir.vip_path).nonEmpty
    }

    private static func residentBytes(_ pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return 0 }
        return info.pti_resident_size
    }

    /// argv via `KERN_PROCARGS2`: Int32 argc, exec path, NUL padding, then argc C strings.
    private static func arguments(_ pid: Int32) -> [String] {
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMib, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        var size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip exec path.
        while index < size, buffer[index] != 0 { index += 1 }
        // Skip NUL padding.
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while args.count < Int(argc), index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }

    /// Decodes a fixed-size C char tuple up to its first NUL (or its full length).
    private static func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
