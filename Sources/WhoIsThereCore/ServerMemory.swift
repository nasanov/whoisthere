import Foundation

public struct Remembered: Codable, Equatable, Sendable {
    public var starter: Starter?
    public var git: GitInfo?
    public init(starter: Starter?, git: GitInfo?) {
        self.starter = starter
        self.git = git
    }
}

public final class ServerMemory: @unchecked Sendable {
    private struct Entry: Codable {
        var identity: ProcessIdentity
        var value: Remembered
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var store: [ProcessIdentity: Remembered] = [:]
    private var dirty = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            for e in entries { store[e.identity] = e.value }
        }
    }

    public func recall(_ id: ProcessIdentity) -> Remembered? {
        lock.lock(); defer { lock.unlock() }
        return store[id]
    }

    public func remember(_ id: ProcessIdentity, _ value: Remembered) {
        lock.lock(); defer { lock.unlock() }
        if store[id] != value {
            store[id] = value
            dirty = true
        }
    }

    public func prune(keeping: Set<ProcessIdentity>) {
        lock.lock(); defer { lock.unlock() }
        let before = store.count
        store = store.filter { keeping.contains($0.key) }
        if store.count != before { dirty = true }
    }

    public func save() throws {
        lock.lock(); defer { lock.unlock() }
        guard dirty else { return }
        let entries = store.map { Entry(identity: $0.key, value: $0.value) }
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        dirty = false
    }
}
