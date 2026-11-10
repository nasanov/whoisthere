import Foundation
import Observation

@MainActor @Observable
public final class ServerStore {
    public private(set) var servers: [DevServer] = []

    public var showAll: Bool = false {
        didSet {
            guard showAll != oldValue else { return }
            Task { await refresh() }
        }
    }

    public var isMenuOpen: Bool = false {
        didSet {
            guard isMenuOpen != oldValue, pollTask != nil else { return }
            startLoop(refreshImmediately: isMenuOpen)
        }
    }

    public var pollInterval: Duration { isMenuOpen ? .seconds(2) : .seconds(12) }

    @ObservationIgnored private let source: ProcessSource
    @ObservationIgnored private let builder: ServerBuilder
    @ObservationIgnored private let memory: ServerMemory
    @ObservationIgnored private let killer: Killer
    @ObservationIgnored private let currentUID: UInt32
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    public init(source: ProcessSource, builder: ServerBuilder, memory: ServerMemory,
                killer: Killer, currentUID: UInt32) {
        self.source = source
        self.builder = builder
        self.memory = memory
        self.killer = killer
        self.currentUID = currentUID
    }

    public func start() {
        guard pollTask == nil else { return }
        startLoop(refreshImmediately: true)
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let source = source, builder = builder, memory = memory, showAll = showAll
        let result = await Task.detached(priority: .userInitiated) { () -> [DevServer]? in
            guard let snapshot = try? source.snapshot() else { return nil }
            return builder.build(snapshot: snapshot, showAll: showAll, memory: memory)
        }.value
        // A newer refresh started meanwhile; its result supersedes this (possibly stale) one.
        guard let result, generation == refreshGeneration else { return }
        if result != servers { servers = result }
        try? memory.save()
    }

    public func kill(_ server: DevServer) async {
        let source = source, killer = killer, currentUID = currentUID
        // Unstructured so cancelling the caller can't cut the grace period short.
        let work = Task {
            let targets = await Task.detached(priority: .userInitiated) { () -> [ProcessIdentity] in
                guard let snapshot = try? source.snapshot() else { return [] }
                return KillPlanner.targets(for: server.id, snapshot: snapshot, currentUID: currentUID,
                                           enrich: { source.enrich($0) })
            }.value
            if !targets.isEmpty { await killer.terminate(targets) }
            await self.refresh()
        }
        await work.value
    }

    private func startLoop(refreshImmediately: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var first = refreshImmediately
            // No strong reference to the store is held across the sleep.
            while !Task.isCancelled, let interval = await self?.tick(refresh: first) {
                first = true
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func tick(refresh shouldRefresh: Bool) async -> Duration {
        if shouldRefresh { await refresh() }
        return pollInterval
    }
}
