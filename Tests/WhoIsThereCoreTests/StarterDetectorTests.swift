import Foundation
import Testing
@testable import WhoIsThereCore

private func proc(_ pid: Int32, _ name: String, path: String? = nil, args: [String] = []) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: 0, uid: 501, name: name, executablePath: path, arguments: args,
                  cwd: nil, startTime: Date(timeIntervalSince1970: 0), residentBytes: 0, listeningPorts: [])
}

@Test func claudeBeatsFartherTerminal() {
    let chain = [proc(500, "zsh"), proc(400, "claude"), proc(300, "zsh"), proc(200, "Ghostty")]
    #expect(StarterDetector.detect(ancestors: chain) == .claude)
}

@Test func claudeCodeArgumentMatches() {
    let chain = [proc(500, "node", args: ["node", "/x/@anthropic-ai/claude-code/cli.js"])]
    #expect(StarterDetector.detect(ancestors: chain) == .claude)
}

@Test func terminalDetected() {
    let chain = [proc(500, "zsh"), proc(400, "login"), proc(300, "Terminal")]
    #expect(StarterDetector.detect(ancestors: chain) == .terminal)
}

@Test func editorsDetectedByPath() {
    let paths: [(String, String)] = [
        ("/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper", "VS Code"),
        ("/Applications/Cursor.app/Contents/MacOS/Cursor", "Cursor"),
        ("/Applications/Zed.app/Contents/MacOS/zed", "Zed"),
        ("/Applications/Xcode.app/Contents/MacOS/Xcode", "Xcode"),
    ]
    for (path, label) in paths {
        let chain = [proc(500, "zsh"), proc(400, "Code Helper", path: path)]
        #expect(StarterDetector.detect(ancestors: chain) == .editor(label))
    }
}

@Test func stopsAtPid1() {
    #expect(StarterDetector.detect(ancestors: [proc(1, "launchd")]) == nil)
    let chain = [proc(500, "zsh"), proc(1, "launchd"), proc(300, "Terminal")]
    #expect(StarterDetector.detect(ancestors: chain) == nil)
}

@Test func noMatchIsNil() {
    #expect(StarterDetector.detect(ancestors: [proc(500, "zsh"), proc(400, "sshd")]) == nil)
}

@Test func classifySingleProcess() {
    #expect(StarterDetector.classify(proc(5, "claude")) == .claude)
    #expect(StarterDetector.classify(proc(5, "tmux")) == .terminal)
    #expect(StarterDetector.classify(proc(5, "node")) == nil)
}

// MARK: - Claude predicate (native install, npm install, no over-matching)

@Test func nativeClaudeInstallIsClaude() {
    // Real shape: proc_pidpath basename is the version number, argv[0] is "claude".
    let native = proc(77285, "2.1.306", path: "/Users/me/.local/share/claude/versions/2.1.306",
                      args: ["claude", "--output-format", "stream-json", "--verbose"])
    #expect(StarterDetector.classify(native) == .claude)
    #expect(StarterDetector.isClaude(native))
    // Same binary seen before enrichment (no argv): the versions path alone suffices.
    #expect(StarterDetector.isClaude(proc(1, "2.1.306", path: "/Users/me/.local/share/claude/versions/2.1.306")))
    // argv[0] given as a full path.
    #expect(StarterDetector.isClaude(proc(1, "x", args: ["/Users/me/.local/bin/claude", "-p"])))
}

@Test func npmClaudeInstallIsClaude() {
    let p = proc(1, "node", args: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"])
    #expect(StarterDetector.isClaude(p))
}

@Test func claudeCodeNamedProjectIsNotClaude() {
    let p = proc(1, "node", path: "/usr/local/bin/node",
                 args: ["node", "/Users/me/code/claude-code-ui/node_modules/.bin/vite"])
    #expect(!StarterDetector.isClaude(p))
    #expect(StarterDetector.classify(p) == nil)
}

@Test func moreTerminalsAndEditors() {
    let terminals: [ProcessRecord] = [
        proc(1, "Hyper", path: "/Applications/Hyper.app/Contents/MacOS/Hyper"),
        proc(1, "Tabby", path: "/Applications/Tabby.app/Contents/MacOS/Tabby"),
        proc(1, "rio", path: "/Applications/Rio.app/Contents/MacOS/rio"),
    ]
    for t in terminals { #expect(StarterDetector.classify(t) == .terminal) }

    let editors: [(String, String)] = [
        ("/Applications/WebStorm.app/Contents/MacOS/webstorm", "WebStorm"),
        ("/Applications/IntelliJ IDEA.app/Contents/MacOS/idea", "IntelliJ IDEA"),
        ("/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea", "IntelliJ IDEA"),
        ("/Users/me/Applications/PyCharm Professional Edition.app/Contents/MacOS/pycharm", "PyCharm"),
        ("/Applications/GoLand.app/Contents/MacOS/goland", "GoLand"),
        ("/Applications/RubyMine.app/Contents/MacOS/rubymine", "RubyMine"),
        ("/Applications/PhpStorm.app/Contents/MacOS/phpstorm", "PhpStorm"),
        ("/Applications/RustRover.app/Contents/MacOS/rustrover", "RustRover"),
        ("/Applications/CLion.app/Contents/MacOS/clion", "CLion"),
        ("/Applications/Windsurf.app/Contents/MacOS/Electron", "Windsurf"),
        // Real shape on this machine: T3 Code's server process spawns the terminal shells.
        ("/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)", "T3 Code"),
        ("/Applications/T3 Code.app/Contents/MacOS/T3 Code", "T3 Code"),
    ]
    for (path, label) in editors {
        #expect(StarterDetector.classify(proc(1, (path as NSString).lastPathComponent, path: path))
            == .editor(label), "\(path)")
    }
    // A project folder merely named like an IDE is not an editor.
    #expect(StarterDetector.classify(proc(1, "node", path: "/Users/me/WebStorm/node")) == nil)
}
