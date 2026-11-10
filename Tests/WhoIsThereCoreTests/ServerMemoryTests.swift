import Foundation
import Testing
@testable import WhoIsThereCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("whoisthere-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("memory.json")
}

@Test func memoryRoundTrips() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let a = ProcessIdentity(pid: 10, startTime: Date(timeIntervalSince1970: 1_700_000_000.123456))
    let b = ProcessIdentity(pid: 11, startTime: Date(timeIntervalSince1970: 1_700_000_001.987654))
    let va = Remembered(starter: .editor("Zed"), git: GitInfo(repoName: "r", branch: "main", isWorktree: true))
    let vb = Remembered(starter: .claude, git: nil)

    let m = ServerMemory(fileURL: url)
    m.remember(a, va)
    m.remember(b, vb)
    try m.save()

    let m2 = ServerMemory(fileURL: url)
    #expect(m2.recall(a) == va)
    #expect(m2.recall(b) == vb)
    #expect(m2.recall(ProcessIdentity(pid: 12, startTime: a.startTime)) == nil)
}

@Test func pruneRemovesUnkept() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let a = ProcessIdentity(pid: 1, startTime: Date(timeIntervalSince1970: 1))
    let b = ProcessIdentity(pid: 2, startTime: Date(timeIntervalSince1970: 2))
    let m = ServerMemory(fileURL: url)
    m.remember(a, Remembered(starter: .terminal, git: nil))
    m.remember(b, Remembered(starter: .claude, git: nil))
    m.prune(keeping: [a])
    #expect(m.recall(a) != nil)
    #expect(m.recall(b) == nil)
    try m.save()
    #expect(ServerMemory(fileURL: url).recall(b) == nil)
}

@Test func corruptFileLoadsEmpty() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json {{".utf8).write(to: url)
    let m = ServerMemory(fileURL: url)
    #expect(m.recall(ProcessIdentity(pid: 1, startTime: Date(timeIntervalSince1970: 1))) == nil)
}

@Test func saveOnlyWritesWhenChanged() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let m = ServerMemory(fileURL: url)
    try m.save()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    m.remember(ProcessIdentity(pid: 1, startTime: Date(timeIntervalSince1970: 1)), Remembered(starter: nil, git: nil))
    try m.save()
    #expect(FileManager.default.fileExists(atPath: url.path))
    try FileManager.default.removeItem(at: url)
    try m.save()
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
