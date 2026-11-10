import Testing
import Foundation
import os
@testable import WhoIsThereCore

@Suite struct LiveProcessSourceTests {
    /// Spawns `python3 -m http.server 0` in `dir` and waits (up to `timeout`) for its port.
    private func spawnServer(in dir: URL, timeout: TimeInterval = 5) throws -> (Process, UInt16?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-m", "http.server", "0", "--bind", "127.0.0.1"]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = OSAllocatedUnfairLock(initialState: "")
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            output.withLock { $0 += String(decoding: data, as: UTF8.self) }
        }
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = output.withLock { $0 }
            if let match = text.firstMatch(of: /port (\d+)/), let port = UInt16(match.1) {
                return (process, port)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (process, nil)
    }

    private func realpath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @Test func includesOtherUserProcessesAndFullAncestorChain() throws {
        let records = try LiveProcessSource().snapshot()
        let byPid = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        let launchd = try #require(byPid[1], "pid 1 missing from snapshot")
        #expect(launchd.uid == 0)
        #expect(launchd.startTime.timeIntervalSince1970 > 0)

        // The test runner's ancestor chain reaches launchd through the snapshot.
        var current: Int32? = getpid()
        var hops = 0
        while let pid = current, pid != 1, hops < 64 {
            current = byPid[pid]?.ppid
            hops += 1
        }
        #expect(current == 1)
    }

    @Test func sysctlFallbackMatchesBsdInfo() throws {
        // Start time is identity, so both sources must agree for the same process.
        let viaBsd = try #require(LiveProcessSource.bsdInfo(getpid()))
        let viaSysctl = try #require(LiveProcessSource.kinfoInfo(getpid()))
        #expect(viaSysctl.startTime == viaBsd.startTime)
        #expect(viaSysctl.ppid == viaBsd.ppid)
        #expect(viaSysctl.uid == viaBsd.uid)
        #expect(LiveProcessSource.kinfoInfo(1)?.uid == 0)
    }

    @Test func enrichFillsPathAndArguments() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        let pid = process.processIdentifier
        let info = try #require(LiveProcessSource.basicInfo(pid))
        let bare = ProcessRecord(pid: pid, ppid: info.ppid, uid: info.uid, name: info.comm,
                                 executablePath: nil, arguments: [], cwd: nil,
                                 startTime: info.startTime, residentBytes: 0, listeningPorts: [])

        let enriched = LiveProcessSource().enrich(bare)
        #expect(enriched.executablePath == "/bin/sleep")
        #expect(enriched.name == "sleep")
        #expect(enriched.arguments == ["/bin/sleep", "30"])
        #expect(enriched.startTime == bare.startTime)
    }

    @Test func findsSpawnedServer() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoisthere-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let (process, port) = try spawnServer(in: dir)
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        let serverPort = try #require(port, "python http.server did not report a port within 5 s")

        let source = LiveProcessSource()
        let records = try source.snapshot()
        let byPid = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        let server = try #require(byPid[process.processIdentifier])
        #expect(server.listeningPorts.contains(serverPort))
        #expect(server.cwd.map(realpath) == realpath(dir.path))
        #expect(server.arguments.contains("http.server"))

        // Parent chain reaches the test runner.
        var current: Int32? = server.ppid
        var hops = 0
        var reachedRunner = false
        while let pid = current, pid > 1, hops < 64 {
            if pid == getpid() { reachedRunner = true; break }
            current = byPid[pid]?.ppid
            hops += 1
        }
        #expect(reachedRunner)

        // Start time is identity: it must be stable across snapshots.
        let again = try source.snapshot().first { $0.pid == server.pid }
        #expect(again?.startTime == server.startTime)

        // Informational timing (no assertion, to keep the suite non-flaky).
        let start = ContinuousClock.now
        let listening = try source.snapshot().filter { !$0.listeningPorts.isEmpty }.count
        let elapsed = ContinuousClock.now - start
        print("LiveProcessSource: \(listening) listening processes, snapshot took \(elapsed)")
    }
}
