import Testing
import Foundation
@testable import WhoIsThereCore

struct DevServerFilterTests {
    let home = "/Users/a"

    func rec(name: String = "node", uid: UInt32 = 501, path: String? = "/usr/local/bin/node",
             args: [String] = ["node"], cwd: String? = "/Users/a/code/x",
             ports: [UInt16] = [3000]) -> ProcessRecord {
        ProcessRecord(pid: 100, ppid: 1, uid: uid, name: name, executablePath: path, arguments: args,
                      cwd: cwd, startTime: Date(timeIntervalSince1970: 0), residentBytes: 0, listeningPorts: ports)
    }

    func inc(_ p: ProcessRecord, showAll: Bool = false) -> Bool {
        DevServerFilter.includes(p, home: home, currentUID: 501, showAll: showAll)
    }

    @Test func includesNodeInHome() { #expect(inc(rec())) }
    @Test func excludesDenyListed() { #expect(!inc(rec(name: "postgres"))) }
    @Test func excludesCwdRoot() { #expect(!inc(rec(cwd: "/"))) }
    @Test func excludesHomeItself() { #expect(!inc(rec(cwd: "/Users/a"))) }
    @Test func excludesOtherUID() { #expect(!inc(rec(uid: 502))) }
    @Test func excludesAppBundles() {
        #expect(!inc(rec(name: "Cursor", path: "/Applications/Cursor.app/Contents/MacOS/Cursor")))
    }
    @Test func includesBundledPythonRuntime() {
        let p = rec(name: "Python",
                    path: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python",
                    args: ["python3", "-m", "http.server", "8000"], ports: [8000])
        #expect(inc(p))
        #expect(DevServerFilter.looksHTTP(p, framework: nil))
    }
    @Test func excludesAppHelperEvenWithPort() {
        #expect(!inc(rec(name: "Cursor Helper (Plugin)",
                         path: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)")))
    }
    @Test func showAllIncludesDenyListed() { #expect(inc(rec(name: "postgres", cwd: "/"), showAll: true)) }
    @Test func showAllStillRequiresOwnerAndPort() {
        #expect(!inc(rec(uid: 502), showAll: true))
        #expect(!inc(rec(ports: []), showAll: true))
    }

    @Test func visiblePortsDropsInspector() {
        let p = rec(args: ["node", "--inspect", "app.js"], ports: [3000, 3000, 24678, 9229])
        #expect(DevServerFilter.visiblePorts(p) == [3000, 24678])
    }
    @Test func visiblePortsDropsExplicitInspectPort() {
        let p = rec(args: ["node", "--inspect-brk=127.0.0.1:9333"], ports: [9333, 9229, 3000])
        #expect(DevServerFilter.visiblePorts(p) == [3000])
    }
    @Test func visiblePortsKeepsAllWithoutInspect() {
        #expect(DevServerFilter.visiblePorts(rec(ports: [9229, 3000])) == [3000, 9229])
    }

    @Test func looksHTTP() {
        #expect(DevServerFilter.looksHTTP(rec(), framework: nil))
        #expect(DevServerFilter.looksHTTP(rec(name: "weird"), framework: .vite))
        #expect(!DevServerFilter.looksHTTP(rec(name: "weird"), framework: nil))
    }
}

extension DevServerFilterTests {
    @Test func excludesNativeClaudeButNotClaudeCodeNamedProject() {
        let claude = rec(name: "2.1.306", path: "/Users/a/.local/share/claude/versions/2.1.306",
                         args: ["claude", "--verbose"], ports: [51234])
        #expect(!inc(claude))
        let project = rec(args: ["node", "/Users/a/code/claude-code-ui/node_modules/.bin/vite"])
        #expect(inc(project))
    }
}
