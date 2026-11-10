import Darwin
import Foundation
import Testing
@testable import WhoIsThereCore

private let uid: UInt32 = 501
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private struct Boom: Error {}

private final class FakeSource: ProcessSource, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [ProcessRecord]
    private var failing = false

    init(_ records: [ProcessRecord]) { self.records = records }

    func set(_ records: [ProcessRecord]) { lock.withLock { self.records = records } }
    func setFailing(_ value: Bool) { lock.withLock { failing = value } }

    func snapshot() throws -> [ProcessRecord] {
        try lock.withLock {
            if failing { throw Boom() }
            return records
        }
    }
}

/// First snapshot() call blocks until released and returns `stale`; later calls return `fresh`.
private final class SlowFirstSource: ProcessSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let stale: [ProcessRecord], fresh: [ProcessRecord]
    let firstStarted = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func waitForFirst() { firstStarted.wait() }

    init(stale: [ProcessRecord], fresh: [ProcessRecord]) { self.stale = stale; self.fresh = fresh }

    func snapshot() throws -> [ProcessRecord] {
        let n = lock.withLock { calls += 1; return calls }
        if n == 1 {
            firstStarted.signal()
            release.wait()
            return stale
        }
        return fresh
    }
}

private final class FakeSignaler: ProcessSignaler, @unchecked Sendable {
    private let lock = NSLock()
    private var alive: [Int32: Date] = [:]
    private var sent: [(Int32, Int32)] = []
    var ignoreTerm = false
    var onSend: (@Sendable (Int32, Int32) -> Void)?

    init(alive: [Int32: Date]) { self.alive = alive }

    func startTime(of pid: Int32) -> Date? { lock.withLock { alive[pid] } }

    func send(_ signal: Int32, to pid: Int32) {
        lock.withLock {
            sent.append((signal, pid))
            if signal == SIGKILL || (signal == SIGTERM && !ignoreTerm) { alive[pid] = nil }
        }
        onSend?(signal, pid)
    }

    var signals: [(Int32, Int32)] { lock.withLock { sent } }
}

private func server(pid: Int32 = 100) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: 1, uid: uid, name: "node", executablePath: nil,
                  arguments: ["node", "server.js"], cwd: "/Users/me/proj", startTime: t0,
                  residentBytes: 1000, listeningPorts: [3000])
}

@MainActor
private func makeStore(source: ProcessSource, signaler: FakeSignaler,
                       grace: Duration = .milliseconds(50)) -> ServerStore {
    let builder = ServerBuilder(home: "/Users/me", currentUID: uid, fileExists: { _ in true },
                                resolveGit: { _ in nil }, readPackageJSON: { _ in nil })
    let memory = ServerMemory(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("whoisthere-\(UUID().uuidString)/memory.json"))
    let killer = Killer(signaler: signaler, grace: grace, pollInterval: .milliseconds(10))
    return ServerStore(source: source, builder: builder, memory: memory, killer: killer, currentUID: uid)
}

@MainActor
@Suite struct ServerStoreTests {
    @Test func refreshPopulates() async {
        let store = makeStore(source: FakeSource([server()]), signaler: FakeSignaler(alive: [:]))
        await store.refresh()
        #expect(store.servers.count == 1)
        #expect(store.servers.first?.primaryPort == 3000)
    }

    @Test func intervalFollowsMenu() {
        let store = makeStore(source: FakeSource([]), signaler: FakeSignaler(alive: [:]))
        #expect(store.pollInterval == .seconds(12))
        store.isMenuOpen = true
        #expect(store.pollInterval == .seconds(2))
    }

    @Test func killRemovesRow() async {
        let source = FakeSource([server()])
        let signaler = FakeSignaler(alive: [100: t0])
        signaler.onSend = { signal, pid in
            if signal == SIGTERM && pid == 100 { source.set([]) }
        }
        let store = makeStore(source: source, signaler: signaler)
        await store.refresh()
        #expect(store.servers.count == 1)

        await store.kill(store.servers[0])
        #expect(store.servers.isEmpty)
        #expect(signaler.signals.contains { $0.0 == SIGTERM && $0.1 == 100 })
    }

    @Test func snapshotErrorKeepsLastList() async {
        let source = FakeSource([server()])
        let store = makeStore(source: source, signaler: FakeSignaler(alive: [:]))
        await store.refresh()
        source.setFailing(true)
        await store.refresh()
        #expect(store.servers.count == 1)
    }

    @Test func killSurvivesCallerCancellation() async throws {
        let source = FakeSource([server()])
        let signaler = FakeSignaler(alive: [100: t0])
        signaler.ignoreTerm = true // stays alive until SIGKILL
        let store = makeStore(source: source, signaler: signaler, grace: .milliseconds(200))
        await store.refresh()
        let target = store.servers[0]
        let caller = Task { await store.kill(target) }
        try await Task.sleep(for: .milliseconds(60)) // inside the grace period
        caller.cancel()
        await caller.value
        #expect(signaler.signals.contains { $0.0 == SIGTERM && $0.1 == 100 })
        #expect(signaler.signals.contains { $0.0 == SIGKILL && $0.1 == 100 })
    }

    @Test func staleRefreshDoesNotOverwriteNewer() async {
        let source = SlowFirstSource(stale: [server(pid: 100)], fresh: [])
        let store = makeStore(source: source, signaler: FakeSignaler(alive: [:]))
        let first = Task { await store.refresh() }
        await Task.detached { source.waitForFirst() }.value
        await store.refresh() // newer, returns fresh (empty)
        source.release.signal()
        await first.value
        #expect(store.servers.isEmpty)
    }

    @Test func refreshPriorityFollowsMenu() {
        let store = makeStore(source: FakeSource([]), signaler: FakeSignaler(alive: [:]))
        #expect(store.refreshPriority == .utility)
        store.isMenuOpen = true
        #expect(store.refreshPriority == .userInitiated)
    }

    @Test func killingTracksInProgressKill() async throws {
        let source = FakeSource([server()])
        let signaler = FakeSignaler(alive: [100: t0])
        signaler.ignoreTerm = true // alive through the grace period
        let store = makeStore(source: source, signaler: signaler, grace: .milliseconds(300))
        await store.refresh()
        let target = store.servers[0]
        #expect(store.killing.isEmpty)
        let kill = Task { await store.kill(target) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.killing == [target.id])
        await kill.value
        #expect(store.killing.isEmpty)
    }
}
