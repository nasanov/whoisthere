import Foundation
import Testing
@testable import WhoIsThereCore

private let home = "/Users/me"
private let uid: UInt32 = 501
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func rec(_ pid: Int32, ppid: Int32 = 1, name: String = "node", args: [String] = [],
                 cwd: String? = "/Users/me/proj", ports: [UInt16] = [], path: String? = nil) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: ppid, uid: uid, name: name, executablePath: path, arguments: args,
                  cwd: cwd, startTime: t0, residentBytes: 1000, listeningPorts: ports)
}

private func memory() -> ServerMemory {
    ServerMemory(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("whoisthere-\(UUID().uuidString)/memory.json"))
}

private func builder(exists: @Sendable @escaping (String) -> Bool = { _ in true },
                     git: GitInfo? = nil) -> ServerBuilder {
    ServerBuilder(home: home, currentUID: uid, fileExists: exists,
                  resolveGit: { _ in git }, readPackageJSON: { _ in nil })
}

private let chain = [
    rec(100, ppid: 1, name: "zsh", cwd: "/Users/me"),
    rec(200, ppid: 100, name: "claude", cwd: "/Users/me/proj"),
]

@Test func groupsPorts() {
    let s = builder().build(snapshot: [rec(300, ports: [5173, 5173, 24678])], showAll: false, memory: memory())
    #expect(s.count == 1)
    #expect(s[0].primaryPort == 5173)
    #expect(s[0].otherPorts == [24678])
}

@Test func claudeStarter() {
    let mem = memory()
    let server = rec(300, ppid: 200, ports: [3000])
    let s = builder().build(snapshot: chain + [server], showAll: false, memory: mem)
    #expect(s[0].starter == .claude)
    #expect(mem.recall(server.identity)?.starter == .claude)
}

@Test func starterSurvivesOrphaning() {
    let mem = memory()
    let b = builder()
    _ = b.build(snapshot: chain + [rec(300, ppid: 200, ports: [3000])], showAll: false, memory: mem)
    let s = b.build(snapshot: [rec(300, ppid: 1, ports: [3000])], showAll: false, memory: mem)
    #expect(s[0].starter == .claude)
    #expect(s[0].stale == .sessionClosed)
}

@Test func deletedWorktree() {
    let mem = memory()
    let git = GitInfo(repoName: "repo", branch: "feat", isWorktree: true)
    let snap = [rec(300, ports: [3000])]
    _ = builder(git: git).build(snapshot: snap, showAll: false, memory: mem)
    let s = builder(exists: { _ in false }).build(snapshot: snap, showAll: false, memory: mem)
    #expect(s[0].stale == .worktreeDeleted)
    #expect(s[0].projectName == "repo")
    #expect(s[0].branch == "feat")
}

@Test func deletedPlainFolder() {
    let s = builder(exists: { _ in false }).build(snapshot: [rec(300, ports: [3000])], showAll: false, memory: memory())
    #expect(s[0].stale == .folderDeleted)
    #expect(s[0].projectName == "proj")
}

@Test func sortedByPort() {
    let snap = [rec(1001, ports: [5173]), rec(1002, ports: [3000]), rec(1003, ports: [3001])]
    let s = builder().build(snapshot: snap, showAll: false, memory: memory())
    #expect(s.map { $0.primaryPort } == [3000, 3001, 5173])
}

@Test func nonHTTP() {
    let s = builder().build(snapshot: [rec(300, name: "erl", ports: [4369])], showAll: false, memory: memory())
    #expect(s[0].url == nil)
}

@Test func pruneKeepsAllSnapshotIdentities() {
    let mem = memory()
    let hidden = rec(400, name: "postgres", ports: [5432])
    mem.remember(hidden.identity, Remembered(starter: .terminal, git: nil))
    _ = builder().build(snapshot: [hidden], showAll: false, memory: mem)
    #expect(mem.recall(hidden.identity) != nil)
}

@Test func defaultPathExistsDistinguishesMissingFromPresent() {
    #expect(!ServerBuilder.pathExists("/nonexistent-\(UUID().uuidString)/x"))
    #expect(!ServerBuilder.pathExists("/etc/hosts/child"))  // ENOTDIR
    #expect(ServerBuilder.pathExists(NSTemporaryDirectory()))
    #expect(ServerBuilder.pathExists("/etc/hosts"))
}
