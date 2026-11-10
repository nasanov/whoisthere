import Foundation

public struct ServerBuilder: Sendable {
    private let home: String
    private let currentUID: UInt32
    private let fileExists: @Sendable (String) -> Bool
    private let resolveGit: @Sendable (String) -> GitInfo?
    private let readPackageJSON: @Sendable (String) -> Data?

    public init(home: String, currentUID: UInt32,
                fileExists: @Sendable @escaping (String) -> Bool = { ServerBuilder.pathExists($0) },
                resolveGit: @Sendable @escaping (String) -> GitInfo? = { GitResolver.resolve(cwd: $0) },
                readPackageJSON: (@Sendable (String) -> Data?)? = nil) {
        self.home = home
        self.currentUID = currentUID
        self.fileExists = fileExists
        self.resolveGit = resolveGit
        self.readPackageJSON = readPackageJSON ?? { Self.nearestPackageJSON(from: $0, home: home) }
    }

    public func build(snapshot: [ProcessRecord], showAll: Bool, memory: ServerMemory) -> [DevServer] {
        let byPID = Dictionary(snapshot.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var servers: [DevServer] = []

        for p in snapshot where DevServerFilter.includes(p, home: home, currentUID: currentUID, showAll: showAll) {
            let ports = DevServerFilter.visiblePorts(p)
            guard let primary = ports.first else { continue }

            let id = p.identity
            let remembered = memory.recall(id)
            let folderExists = p.cwd.map(fileExists) ?? false
            let git: GitInfo? = folderExists ? p.cwd.flatMap(resolveGit) : remembered?.git
            let starter = remembered != nil
                ? remembered?.starter
                : StarterDetector.detect(ancestors: ancestors(of: p, in: byPID))
            if remembered == nil {
                memory.remember(id, Remembered(starter: starter, git: git))
            }

            let packageJSON = folderExists ? p.cwd.flatMap(readPackageJSON) : nil
            let framework = FrameworkDetector.detect(arguments: p.arguments, packageJSON: packageJSON)

            let stale: StaleReason?
            if !folderExists {
                stale = (git?.isWorktree ?? false) ? .worktreeDeleted : .folderDeleted
            } else if p.ppid == 1 {
                stale = .sessionClosed
            } else {
                stale = nil
            }

            servers.append(DevServer(
                id: id, pid: p.pid, primaryPort: primary, otherPorts: Array(ports.dropFirst()),
                projectName: git?.repoName ?? p.cwd.map { ($0 as NSString).lastPathComponent } ?? p.name,
                branch: git?.branch, folder: p.cwd ?? "", framework: framework, starter: starter,
                startTime: p.startTime, residentBytes: p.residentBytes,
                command: p.arguments.isEmpty ? p.name : p.arguments.joined(separator: " "),
                isHTTP: DevServerFilter.looksHTTP(p, framework: framework), stale: stale))
        }

        memory.prune(keeping: Set(snapshot.map(\.identity)))
        return servers.sorted { ($0.primaryPort, $0.pid) < ($1.primaryPort, $1.pid) }
    }

    /// Parent chain, nearest first. Includes the pid-1 record if present, then stops.
    private func ancestors(of p: ProcessRecord, in byPID: [Int32: ProcessRecord]) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var seen: Set<Int32> = [p.pid]
        var current = p
        while current.pid > 1, let parent = byPID[current.ppid], seen.insert(parent.pid).inserted {
            result.append(parent)
            current = parent
        }
        return result
    }

    /// False only when the path is definitely gone (ENOENT / ENOTDIR). Any other failure,
    /// notably EPERM/EACCES from macOS privacy protection (TCC) on Desktop/Documents/Downloads,
    /// counts as existing, so a denied folder never shows as "folder deleted".
    public static func pathExists(_ path: String) -> Bool {
        var st = stat()
        if lstat(path, &st) == 0 { return true }
        return errno != ENOENT && errno != ENOTDIR
    }

    private static func nearestPackageJSON(from cwd: String, home: String) -> Data? {
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        let stop = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path
        while true {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")) { return data }
            if dir.path == stop || dir.path == "/" { return nil }
            dir = dir.deletingLastPathComponent()
        }
    }
}
