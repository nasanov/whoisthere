import Darwin
import Foundation
import Testing
@testable import WhoIsThereCore

private let uid: UInt32 = 501
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func rec(_ pid: Int32, ppid: Int32 = 1, name: String = "node", args: [String] = [],
                 ports: [UInt16] = [], uid: UInt32 = uid, path: String? = nil) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: ppid, uid: uid, name: name, executablePath: path, arguments: args,
                  cwd: "/Users/me/proj", startTime: t0, residentBytes: 1000, listeningPorts: ports)
}

private func pids(_ server: Int32, _ snapshot: [ProcessRecord]) -> Set<Int32> {
    Set(KillPlanner.targets(for: ProcessIdentity(pid: server, startTime: t0),
                            snapshot: snapshot, currentUID: uid).map(\.pid))
}

// MARK: - KillPlanner

@Test func killsServerAndChildren() {
    let snapshot = [rec(50, name: "zsh"), rec(100, ppid: 50, ports: [3000]), rec(101, ppid: 100)]
    #expect(pids(100, snapshot) == [100, 101])
}

@Test func includesNpmWrapper() {
    let snapshot = [
        rec(50, name: "zsh"),
        rec(90, ppid: 50, name: "npm", args: ["npm", "run", "dev"]),
        rec(100, ppid: 90, ports: [3000]),
    ]
    #expect(pids(100, snapshot) == [90, 100])
}

@Test func includesNodeHostedRunners() {
    let npmCli = [rec(90, name: "node", args: ["node", "/opt/lib/npm/bin/npm-cli.js", "run", "dev"]),
                  rec(100, ppid: 90, ports: [3000])]
    #expect(pids(100, npmCli) == [90, 100])

    let bunRun = [rec(90, name: "bun", args: ["/Users/me/.bun/bin/bun", "run", "dev"]),
                  rec(100, ppid: 90, ports: [3000])]
    #expect(pids(100, bunRun) == [90, 100])

    let bunServe = [rec(90, name: "bun", args: ["bun", "server.ts"]),
                    rec(100, ppid: 90, ports: [3000])]
    #expect(pids(100, bunServe) == [100])
}

@Test func spareSiblingsUnderRunner() {
    let concurrently = [
        rec(80, name: "node", args: ["node", "/proj/node_modules/.bin/concurrently", "a", "b"]),
        rec(100, ppid: 80, ports: [3000]),
        rec(200, ppid: 80, ports: [3001]),
    ]
    #expect(pids(100, concurrently) == [100])

    let npm = [
        rec(80, name: "npm", args: ["npm", "run", "dev"]),
        rec(100, ppid: 80, ports: [3000]),
        rec(200, ppid: 80, ports: [3001]),
    ]
    #expect(pids(100, npm) == [100])

    // A listening grandchild outside the server's subtree also disqualifies the wrapper.
    let nested = [
        rec(80, name: "npm", args: ["npm", "run", "dev"]),
        rec(100, ppid: 80, ports: [3000]),
        rec(150, ppid: 80, name: "sh"),
        rec(200, ppid: 150, ports: [3001]),
    ]
    #expect(pids(100, nested) == [100])
}

@Test func neverKillsClaudeOrShell() {
    let snapshot = [
        rec(100, ports: [3000]),
        rec(101, ppid: 100, name: "claude"),
        rec(102, ppid: 100, name: "zsh"),
        rec(103, ppid: 100, name: "node", args: ["node", "/x/claude-code/cli.js"]),
        rec(104, ppid: 100, name: "Code Helper", path: "/Applications/Visual Studio Code.app/x"),
        rec(105, ppid: 100, uid: 0),
        rec(106, ppid: 100),
    ]
    #expect(pids(100, snapshot) == [100, 106])
}

@Test func excludedServerOrStaleIdentityYieldsNothing() {
    #expect(pids(100, [rec(100, name: "bash", ports: [3000])]).isEmpty)
    #expect(pids(1, [rec(1, ppid: 0, ports: [3000])]).isEmpty)
    #expect(pids(100, [rec(100, ports: [3000], uid: 0)]).isEmpty)
    #expect(pids(100, []).isEmpty)
    let reused = KillPlanner.targets(for: ProcessIdentity(pid: 100, startTime: t0.addingTimeInterval(5)),
                                     snapshot: [rec(100, ports: [3000])], currentUID: uid)
    #expect(reused.isEmpty)
}

@Test func excludedRootYieldsNothingEvenWithChildren() {
    #expect(pids(100, [rec(100, name: "claude", ports: [3000]), rec(101, ppid: 100)]).isEmpty)
    #expect(pids(100, [rec(100, name: "zsh", ports: [3000]), rec(101, ppid: 100)]).isEmpty)
    #expect(pids(100, [rec(100, ports: [3000], uid: 0), rec(101, ppid: 100)]).isEmpty)
    #expect(pids(100, [rec(100, name: "Code Helper", ports: [3000],
                           path: "/Applications/Visual Studio Code.app/Contents/x"),
                       rec(101, ppid: 100)]).isEmpty)
}

@Test func nestedStarterSubtreeIsSparedButShellsAreWalked() {
    let snapshot = [
        rec(100, ports: [3000]),
        rec(101, ppid: 100, name: "claude"),
        rec(102, ppid: 101),
        rec(103, ppid: 100, name: "sh"),
        rec(104, ppid: 103),
        rec(105, ppid: 100, name: "tmux"),
        rec(106, ppid: 105),
        rec(107, ppid: 100, uid: 0),
        rec(108, ppid: 107),
    ]
    #expect(pids(100, snapshot) == [100, 104])
}

@Test func enrichRevealsClaudeUnderServer() {
    let snapshot = [rec(100, ports: [3000]), rec(101, ppid: 100), rec(102, ppid: 101)]
    let enrich: (ProcessRecord) -> ProcessRecord = { p in
        var p = p
        if p.pid == 101 { p.arguments = ["node", "/opt/lib/node_modules/@anthropic-ai/claude-code/cli.js"] }
        return p
    }
    let targets = KillPlanner.targets(for: ProcessIdentity(pid: 100, startTime: t0), snapshot: snapshot,
                                      currentUID: uid, enrich: enrich)
    #expect(Set(targets.map(\.pid)) == [100])
}

@Test func enrichAppliesToWrapperCandidate() {
    let snapshot = [rec(90, name: "node"), rec(100, ppid: 90, ports: [3000])]
    let enrich: (ProcessRecord) -> ProcessRecord = { p in
        var p = p
        if p.pid == 90 { p.arguments = ["node", "/opt/lib/node_modules/npm/bin/npm-cli.js", "run", "dev"] }
        return p
    }
    let targets = KillPlanner.targets(for: ProcessIdentity(pid: 100, startTime: t0), snapshot: snapshot,
                                      currentUID: uid, enrich: enrich)
    #expect(targets.map(\.pid) == [100, 90])
}

@Test func cyclicSnapshotTerminates() {
    let snapshot = [rec(100, ppid: 101, ports: [3000]), rec(101, ppid: 100)]
    #expect(pids(100, snapshot) == [100, 101])
}

@Test func targetsAreDeduplicated() {
    let snapshot = [rec(100, ports: [3000]), rec(101, ppid: 100), rec(101, ppid: 100)]
    let targets = KillPlanner.targets(for: ProcessIdentity(pid: 100, startTime: t0),
                                      snapshot: snapshot, currentUID: uid)
    #expect(targets.count == 2)
}

// MARK: - Killer

private final class FakeSignaler: ProcessSignaler, @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Int32: Date]
    private let afterTerm: [Int32: Date?]
    private var _sent: [(signal: Int32, pid: Int32)] = []

    /// `afterTerm[pid]` is what `startTime(of:)` reports once SIGTERM was sent
    /// (nil = exited); pids absent from it ignore SIGTERM. SIGKILL always ends a process.
    init(times: [Int32: Date], afterTerm: [Int32: Date?] = [:]) {
        self.times = times
        self.afterTerm = afterTerm
    }

    var sent: [(signal: Int32, pid: Int32)] { lock.withLock { _sent } }

    func startTime(of pid: Int32) -> Date? { lock.withLock { times[pid] } }

    func send(_ signal: Int32, to pid: Int32) {
        lock.withLock {
            _sent.append((signal, pid))
            if signal == SIGKILL {
                times[pid] = nil
            } else if signal == SIGTERM, let next = afterTerm[pid] {
                times[pid] = next
            }
        }
    }
}

private let fast: Duration = .milliseconds(10)

@Test func pidReuseNotSignaled() async {
    let fake = FakeSignaler(times: [100: t0], afterTerm: [100: t0.addingTimeInterval(42)])
    await Killer(signaler: fake, grace: .milliseconds(50), pollInterval: fast)
        .terminate([ProcessIdentity(pid: 100, startTime: t0)])
    #expect(fake.sent.map(\.signal) == [SIGTERM])
}

@Test func escalatesToSigkill() async {
    let fake = FakeSignaler(times: [100: t0])
    let clock = ContinuousClock()
    let start = clock.now
    await Killer(signaler: fake, grace: .milliseconds(50), pollInterval: fast)
        .terminate([ProcessIdentity(pid: 100, startTime: t0)])
    #expect(clock.now - start >= .milliseconds(50))
    #expect(fake.sent.map(\.signal) == [SIGTERM, SIGKILL])
    #expect(fake.sent.allSatisfy { $0.pid == 100 })
}

@Test func gracefulExitSkipsSigkill() async {
    let fake = FakeSignaler(times: [100: t0, 101: t0], afterTerm: [100: Date?.none, 101: Date?.none])
    await Killer(signaler: fake, grace: .seconds(5), pollInterval: fast)
        .terminate([ProcessIdentity(pid: 100, startTime: t0), ProcessIdentity(pid: 101, startTime: t0)])
    #expect(fake.sent.map(\.signal) == [SIGTERM, SIGTERM])
}

@Test func mismatchedIdentityIsNeverSignaled() async {
    let fake = FakeSignaler(times: [100: t0.addingTimeInterval(1), 101: t0])
    await Killer(signaler: fake, grace: .milliseconds(50), pollInterval: fast)
        .terminate([ProcessIdentity(pid: 100, startTime: t0),
                    ProcessIdentity(pid: 101, startTime: t0),
                    ProcessIdentity(pid: 102, startTime: t0)])
    #expect(fake.sent.allSatisfy { $0.pid == 101 })
    #expect(fake.sent.map(\.signal) == [SIGTERM, SIGKILL])
}

@Test func realProcess() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c",
                         "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"]
    try process.run()
    defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }

    // Let python install its SIG_IGN handler so the SIGKILL path is exercised.
    try await Task.sleep(for: .milliseconds(200))
    let signaler = DarwinSignaler()
    let pid = process.processIdentifier
    let started = try #require(signaler.startTime(of: pid))

    await Killer(signaler: signaler, grace: .milliseconds(300), pollInterval: .milliseconds(20))
        .terminate([ProcessIdentity(pid: pid, startTime: started)])

    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while process.isRunning, clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!process.isRunning)
    #expect(process.terminationReason == .uncaughtSignal)
    #expect(process.terminationStatus == SIGKILL)
    #expect(signaler.startTime(of: pid) != started)
}
