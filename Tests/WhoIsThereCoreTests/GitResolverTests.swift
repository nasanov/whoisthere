import Testing
import Foundation
@testable import WhoIsThereCore

@Suite struct GitResolverTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoisthere-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func plainRepo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("ref: refs/heads/main\n", to: root.appendingPathComponent("shop-web/.git/HEAD"))
        let cwd = root.appendingPathComponent("shop-web/apps/web")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        #expect(GitResolver.resolve(cwd: cwd.path)
            == GitInfo(repoName: "shop-web", branch: "main", isWorktree: false))
    }

    @Test func linkedWorktree() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gitdir = root.appendingPathComponent("shop-web/.git/worktrees/cart")
        try write("ref: refs/heads/feat/cart\n", to: gitdir.appendingPathComponent("HEAD"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let wt = root.appendingPathComponent("wt/shop-web-cart")
        try write("gitdir: \(gitdir.path)\n", to: wt.appendingPathComponent(".git"))
        #expect(GitResolver.resolve(cwd: wt.path)
            == GitInfo(repoName: "shop-web", branch: "feat/cart", isWorktree: true))
    }

    @Test func detachedHead() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a1b2c3d4e5f60718293a4b5c6d7e8f9012345678\n",
                  to: root.appendingPathComponent("repo/.git/HEAD"))
        #expect(GitResolver.resolve(cwd: root.appendingPathComponent("repo").path)
            == GitInfo(repoName: "repo", branch: "a1b2c3d", isWorktree: false))
    }

    @Test func notARepo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = root.appendingPathComponent("plain/dir")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        #expect(GitResolver.resolve(cwd: cwd.path) == nil)
    }

    @Test func missingCwd() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoisthere-missing-\(UUID().uuidString)/x").path
        #expect(GitResolver.resolve(cwd: path) == nil)
    }

    /// `git clone --bare url proj/.bare` + `proj/.git` -> "gitdir: ./.bare" + worktrees in `proj/`.
    @Test func dotBareLayout() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("proj")
        let bare = proj.appendingPathComponent(".bare")
        try write("ref: refs/heads/main\n", to: bare.appendingPathComponent("HEAD"))
        try write("gitdir: ./.bare\n", to: proj.appendingPathComponent(".git"))
        let gitdir = bare.appendingPathComponent("worktrees/feat")
        try write("ref: refs/heads/feat\n", to: gitdir.appendingPathComponent("HEAD"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let wt = proj.appendingPathComponent("feat")
        try write("gitdir: \(gitdir.path)\n", to: wt.appendingPathComponent(".git"))

        #expect(GitResolver.resolve(cwd: wt.path)
            == GitInfo(repoName: "proj", branch: "feat", isWorktree: true))
        #expect(GitResolver.resolve(cwd: proj.path)
            == GitInfo(repoName: "proj", branch: "main", isWorktree: false))
    }

    /// `git clone --bare url foo.git` + `git -C foo.git worktree add ../foo-main`.
    @Test func dotGitSuffixedBareRepo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bare = root.appendingPathComponent("code/foo.git")
        try write("ref: refs/heads/main\n", to: bare.appendingPathComponent("HEAD"))
        let gitdir = bare.appendingPathComponent("worktrees/foo-main")
        try write("ref: refs/heads/main\n", to: gitdir.appendingPathComponent("HEAD"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let wt = root.appendingPathComponent("code/foo-main")
        try write("gitdir: \(gitdir.path)\n", to: wt.appendingPathComponent(".git"))

        #expect(GitResolver.resolve(cwd: wt.path)
            == GitInfo(repoName: "foo", branch: "main", isWorktree: true))
    }
}
