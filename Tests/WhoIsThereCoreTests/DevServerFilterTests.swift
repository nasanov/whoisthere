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
        #expect(!inc(rec(path: "/Applications/Cursor.app/Contents/MacOS/Cursor")))
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
