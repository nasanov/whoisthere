import Foundation

public enum StarterDetector {
    private static let terminalNames: Set<String> = [
        "Terminal", "iTerm2", "ghostty", "Ghostty", "WezTerm", "wezterm-gui",
        "alacritty", "kitty", "Warp", "stable", "tmux", "Hyper", "Tabby", "rio", "Rio",
    ]
    private static let terminalBundles: Set<String> = ["Hyper", "Tabby", "Rio"]

    /// Prefix-matched against the name of the outermost `.app` bundle in the executable
    /// path, so variants such as "IntelliJ IDEA CE" or "T3 Code (Beta)" match.
    private static let editorBundles: [(prefix: String, label: String)] = [
        ("Visual Studio Code", "VS Code"),
        ("Cursor", "Cursor"),
        ("Zed", "Zed"),
        ("Xcode", "Xcode"),
        ("Windsurf", "Windsurf"),
        ("T3 Code", "T3 Code"),
        ("IntelliJ IDEA", "IntelliJ IDEA"),
        ("WebStorm", "WebStorm"),
        ("PyCharm", "PyCharm"),
        ("GoLand", "GoLand"),
        ("RubyMine", "RubyMine"),
        ("PhpStorm", "PhpStorm"),
        ("RustRover", "RustRover"),
        ("CLion", "CLion"),
    ]

    /// Language runtimes that may ship inside an editor bundle (e.g. Xcode's
    /// `Python.app`). They run user code, so they are never the editor itself.
    private static let runtimeNames: Set<String> = [
        "node", "bun", "deno", "python", "python3", "ruby", "php", "go", "java",
    ]

    /// Claude Code, however installed: the native binary (`~/.local/bin/claude` ->
    /// `~/.local/share/claude/versions/<version>`, so its name is the version number),
    /// a binary invoked as `claude`, or the npm package run by node.
    public static func isClaude(_ p: ProcessRecord) -> Bool {
        if p.name == "claude" { return true }
        if let first = p.arguments.first, (first as NSString).lastPathComponent == "claude" {
            return true
        }
        if let path = p.executablePath, path.contains("/claude/versions/") { return true }
        return p.arguments.contains { $0.contains("@anthropic-ai/claude-code/") }
    }

    /// Classifies a single process (no ancestor walking).
    public static func classify(_ p: ProcessRecord) -> Starter? {
        if isClaude(p) { return .claude }
        if terminalNames.contains(p.name) { return .terminal }
        guard let bundle = p.executablePath.flatMap(outermostAppBundle) else { return nil }
        if terminalBundles.contains(bundle) { return .terminal }
        if runtimeNames.contains(p.name.lowercased()) { return nil }
        for editor in editorBundles where bundle.hasPrefix(editor.prefix) {
            return .editor(editor.label)
        }
        return nil
    }

    /// `ancestors` is nearest parent first. The first match wins; PID <= 1 stops the walk.
    public static func detect(ancestors: [ProcessRecord]) -> Starter? {
        for p in ancestors {
            if p.pid <= 1 { return nil }
            if let s = classify(p) { return s }
        }
        return nil
    }

    /// "/Applications/Cursor.app/Contents/Frameworks/X.app/..." -> "Cursor".
    private static func outermostAppBundle(_ path: String) -> String? {
        for component in path.split(separator: "/") where component.hasSuffix(".app") {
            return String(component.dropLast(".app".count))
        }
        return nil
    }
}
