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
            // A remembered starter is kept (it survives orphaning). A remembered nil is
            // retried while the process still has a live parent chain to inspect.
            let starter: Starter?
            if let remembered, remembered.starter != nil || p.ppid == 1 {
                starter = remembered.starter
            } else {
                starter = StarterDetector.detect(ancestors: ancestors(of: p, in: byPID))
                if remembered == nil || starter != nil {
                    memory.remember(id, Remembered(starter: starter, git: remembered?.git ?? git))
                }
            }

            let packageJSON = folderExists && FrameworkDetector.isJSRuntime(p)
                ? p.cwd.flatMap(readPackageJSON) : nil
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

    /// Walks up from `cwd`, stopping after the git root (a directory containing `.git`)
    /// or `home`, whichever comes first. A `cwd` outside `home` only checks itself.
    static func nearestPackageJSON(from cwd: String, home: String) -> Data? {
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        let stop = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path
        let insideHome = dir.path.hasPrefix(stop + "/")
        while true {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")) { return data }
            if !insideHome || dir.path == stop || dir.path == "/"
                || pathExists(dir.appendingPathComponent(".git").path) { return nil }
            dir = dir.deletingLastPathComponent()
        }
    }
}
