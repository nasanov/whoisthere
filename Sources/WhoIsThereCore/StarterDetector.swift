import Foundation

public enum StarterDetector {
    private static let terminalNames: Set<String> = [
        "Terminal", "iTerm2", "ghostty", "Ghostty", "WezTerm", "wezterm-gui",
        "alacritty", "kitty", "Warp", "stable", "tmux",
    ]
    private static let editorApps: [(bundle: String, label: String)] = [
        ("Visual Studio Code.app", "VS Code"),
        ("Cursor.app", "Cursor"),
        ("Zed.app", "Zed"),
        ("Xcode.app", "Xcode"),
    ]

    /// Classifies a single process (no ancestor walking).
    public static func classify(_ p: ProcessRecord) -> Starter? {
        if p.name == "claude" || p.arguments.contains(where: { $0.contains("claude-code") }) {
            return .claude
        }
        if terminalNames.contains(p.name) { return .terminal }
        if let path = p.executablePath {
            for editor in editorApps where path.contains(editor.bundle) {
                return .editor(editor.label)
            }
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
}
