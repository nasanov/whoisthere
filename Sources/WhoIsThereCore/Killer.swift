import Darwin
import Foundation

/// Decides exactly which processes a Kill click may signal.
public enum KillPlanner {
    private static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux"]
    private static let runnerNames: Set<String> = ["npm", "pnpm", "yarn", "npx", "pnpx"]
    private static let runnerScripts = ["npm-cli.js", "pnpm.cjs", "yarn.js"]

    /// The server and its descendants, plus its direct parent when that parent is a
    /// package runner with no other listening descendants. Returns `[]` when the server
    /// identity is no longer in the snapshot (exited or PID reused) or the server itself
    /// is excluded. `enrich` fills in details (path, argv) the snapshot may lack; it is
    /// applied to every candidate before it is checked.
    public static func targets(for server: ProcessIdentity, snapshot: [ProcessRecord],
                               currentUID: UInt32,
                               enrich: (ProcessRecord) -> ProcessRecord = { $0 }) -> [ProcessIdentity] {
        var byPid: [Int32: ProcessRecord] = [:]
        var children: [Int32: [ProcessRecord]] = [:]
        for p in snapshot where byPid[p.pid] == nil {
            byPid[p.pid] = p
            children[p.ppid, default: []].append(p)
        }
        guard let found = byPid[server.pid], found.startTime == server.startTime else { return [] }
        let root = enrich(found)
        guard !isExcluded(root, currentUID: currentUID) else { return [] }

        // Breadth-first walk. Shells are spared but walked through (`sh -c` children);
        // barriers (starters, other users, pid <= 1) are spared together with their subtree.
        var seen: Set<Int32> = [root.pid]
        var queue = [root]
        var result = [root]
        var index = 0
        while index < queue.count {
            for raw in children[queue[index].pid] ?? [] where seen.insert(raw.pid).inserted {
                let child = enrich(raw)
                if isBarrier(child, currentUID: currentUID) { continue }
                queue.append(child)
                if !isExcluded(child, currentUID: currentUID) { result.append(child) }
            }
            index += 1
        }

        if let raw = byPid[root.ppid], !seen.contains(raw.pid) {
            let parent = enrich(raw)
            if isPackageRunner(parent), !isExcluded(parent, currentUID: currentUID) {
                let targeted = Set(result.map(\.pid))
                let othersListening = descendants(of: parent.pid, children: children).contains {
                    !targeted.contains($0.pid) && !$0.listeningPorts.isEmpty
                }
                if !othersListening { result.append(parent) }
            }
        }
        return result.map(\.identity)
    }

    /// All descendants of `pid` (cycle-safe, excluding `pid` itself).
    private static func descendants(of pid: Int32,
                                    children: [Int32: [ProcessRecord]]) -> [ProcessRecord] {
        var seen: Set<Int32> = [pid]
        var ordered: [ProcessRecord] = []
        var frontier = [pid]
        while let next = frontier.popLast() {
            for child in children[next] ?? [] where seen.insert(child.pid).inserted {
                ordered.append(child)
                frontier.append(child.pid)
            }
        }
        return ordered
    }

    /// Never signaled, and nothing beneath it is either.
    private static func isBarrier(_ p: ProcessRecord, currentUID: UInt32) -> Bool {
        p.pid <= 1 || p.uid != currentUID || StarterDetector.classify(p) != nil
    }

    private static func isExcluded(_ p: ProcessRecord, currentUID: UInt32) -> Bool {
        isBarrier(p, currentUID: currentUID) || shells.contains(p.name)
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
