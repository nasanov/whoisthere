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
    let chain = [proc(500, "node", args: ["node", "/x/claude-code/cli.js"])]
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
