import Darwin
import Foundation

/// Decides exactly which processes a Kill click may signal.
public enum KillPlanner {
    private static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux"]
    private static let runnerNames: Set<String> = ["npm", "pnpm", "yarn", "npx", "pnpx"]
    private static let runnerScripts = ["npm-cli.js", "pnpm.cjs", "yarn.js"]

    /// The server and its descendants, plus its direct parent when that parent is a
    /// package runner with no other listening descendants. Returns `[]` when the server
    /// identity is no longer in the snapshot (exited or PID reused).
    public static func targets(for server: ProcessIdentity, snapshot: [ProcessRecord],
                               currentUID: UInt32) -> [ProcessIdentity] {
        var byPid: [Int32: ProcessRecord] = [:]
        var children: [Int32: [ProcessRecord]] = [:]
        for p in snapshot where byPid[p.pid] == nil {
            byPid[p.pid] = p
            children[p.ppid, default: []].append(p)
        }
        guard let root = byPid[server.pid], root.startTime == server.startTime else { return [] }

        let serverTree = subtree(of: root, children: children)
        var result = serverTree.filter { !isExcluded($0, currentUID: currentUID) }

        let serverPids = Set(serverTree.map(\.pid))
        if let parent = byPid[root.ppid], !serverPids.contains(parent.pid), isPackageRunner(parent),
           !isExcluded(parent, currentUID: currentUID) {
            let othersListening = subtree(of: parent, children: children).contains {
                $0.pid != parent.pid && !serverPids.contains($0.pid) && !$0.listeningPorts.isEmpty
            }
            if !othersListening { result.append(parent) }
        }
        return result.map(\.identity)
    }

    /// `root` followed by its descendants (breadth-first); each pid appears once.
    private static func subtree(of root: ProcessRecord,
                                children: [Int32: [ProcessRecord]]) -> [ProcessRecord] {
        var seen: Set<Int32> = [root.pid]
        var ordered = [root]
        var index = 0
        while index < ordered.count {
            for child in children[ordered[index].pid] ?? [] where seen.insert(child.pid).inserted {
                ordered.append(child)
            }
            index += 1
        }
        return ordered
    }

    private static func isExcluded(_ p: ProcessRecord, currentUID: UInt32) -> Bool {
        p.pid <= 1 || p.uid != currentUID || shells.contains(p.name)
            || StarterDetector.classify(p) != nil
    }

    private static func isPackageRunner(_ p: ProcessRecord) -> Bool {
        let base = p.arguments.first.map { ($0 as NSString).lastPathComponent }
        if let base, runnerNames.contains(base) { return true }
        if p.arguments.contains(where: { arg in runnerScripts.contains { arg.hasSuffix($0) } }) {
            return true
        }
        if let base, base == "bun" || base == "deno" {
            return p.arguments.dropFirst().contains { $0 == "run" || $0 == "task" }
        }
        return false
    }
}

public protocol ProcessSignaler: Sendable {
    /// nil if not running.
    func startTime(of pid: Int32) -> Date?
    func send(_ signal: Int32, to pid: Int32)
}

/// proc_pidinfo (with the sysctl fallback used by `LiveProcessSource`) + kill(2).
public struct DarwinSignaler: ProcessSignaler {
    public init() {}

    public func startTime(of pid: Int32) -> Date? {
        LiveProcessSource.basicInfo(pid)?.startTime
    }

    public func send(_ signal: Int32, to pid: Int32) {
        guard pid > 1 else { return }
        _ = kill(pid, signal)
    }
}

/// SIGTERM, wait up to `grace`, then SIGKILL survivors. Every signal is preceded by a
/// start-time check so a reused PID is never signaled.
public struct Killer: Sendable {
    private let signaler: ProcessSignaler
    private let grace: Duration
    private let pollInterval: Duration

    public init(signaler: ProcessSignaler = DarwinSignaler(), grace: Duration = .seconds(2),
                pollInterval: Duration = .milliseconds(100)) {
        self.signaler = signaler
        self.grace = grace
        self.pollInterval = pollInterval
    }

    public func terminate(_ targets: [ProcessIdentity]) async {
        var pending: [ProcessIdentity] = []
        for target in targets where isAlive(target) {
            signaler.send(SIGTERM, to: target.pid)
            pending.append(target)
        }

        let clock = ContinuousClock()
        let deadline = clock.now + grace
        while true {
            pending.removeAll { !isAlive($0) }
            if pending.isEmpty || clock.now >= deadline { break }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return // Cancelled: never escalate without the full grace period.
            }
        }

        for target in pending where isAlive(target) {
            signaler.send(SIGKILL, to: target.pid)
        }
    }

    private func isAlive(_ target: ProcessIdentity) -> Bool {
        signaler.startTime(of: target.pid) == target.startTime
    }
}
