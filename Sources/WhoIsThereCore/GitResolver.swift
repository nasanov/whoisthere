import Foundation

public enum GitResolver {
    public static func resolve(cwd: String) -> GitInfo? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else { return nil }

        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var gitIsDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &gitIsDir) {
                return gitIsDir.boolValue
                    ? info(repoName: dir.lastPathComponent, headDir: dotGit, isWorktree: false)
                    : worktreeInfo(dotGitFile: dotGit, base: dir)
            }
            if dir.path == "/" { return nil }
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
    }

    private static func worktreeInfo(dotGitFile: URL, base: URL) -> GitInfo? {
        guard let text = read(dotGitFile), text.hasPrefix("gitdir:") else { return nil }
        let raw = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let gitdir = resolvePath(raw, relativeTo: base)
        // No commondir: the file points at a main git dir (e.g. `gitdir: ./.bare`).
        guard let common = read(gitdir.appendingPathComponent("commondir")), !common.isEmpty else {
            return info(repoName: repoName(commonDir: gitdir), headDir: gitdir, isWorktree: false)
        }
        let commonDir = resolvePath(common, relativeTo: gitdir)
        return info(repoName: repoName(commonDir: commonDir), headDir: gitdir, isWorktree: true)
    }

    /// `proj/.git` and `proj/.bare` -> "proj"; a bare `foo.git` -> "foo"; a bare `foo` -> "foo".
    private static func repoName(commonDir: URL) -> String {
        let name = commonDir.lastPathComponent
        if name == ".git" || name == ".bare" { return commonDir.deletingLastPathComponent().lastPathComponent }
        if name.hasSuffix(".git"), name.count > 4 { return String(name.dropLast(4)) }
        return name
    }

    private static func info(repoName: String, headDir: URL, isWorktree: Bool) -> GitInfo? {
        guard let head = read(headDir.appendingPathComponent("HEAD")), !head.isEmpty else {
            return nil
        }
        let branch: String
        let prefix = "ref: refs/heads/"
        if head.hasPrefix(prefix) {
            branch = String(head.dropFirst(prefix.count))
        } else {
            branch = String(head.prefix(7))
        }
        return GitInfo(repoName: repoName, branch: branch, isWorktree: isWorktree)
    }

    private static func resolvePath(_ path: String, relativeTo base: URL) -> URL {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: path, relativeTo: base)
        return url.standardizedFileURL
    }

    private static func read(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
