import Testing
import Foundation
@testable import WhoIsThereCore

@Suite struct FormattingTests {
    let now = Date(timeIntervalSince1970: 1_000_000_000)

    @Test func uptime() {
        #expect(Format.uptime(from: now.addingTimeInterval(-30), now: now) == "<1m")
        #expect(Format.uptime(from: now.addingTimeInterval(-14 * 60), now: now) == "14m")
        #expect(Format.uptime(from: now.addingTimeInterval(-(2 * 3600 + 300)), now: now) == "2h")
        #expect(Format.uptime(from: now.addingTimeInterval(-26 * 3600), now: now) == "1 day")
        #expect(Format.uptime(from: now.addingTimeInterval(-(3 * 86400 + 4 * 3600)), now: now) == "3 days")
    }

    @Test func abbreviatedPath() {
        #expect(Format.abbreviatedPath("/Users/a/code/x", home: "/Users/a") == "~/code/x")
        #expect(Format.abbreviatedPath("/Users/a", home: "/Users/a") == "~")
        #expect(Format.abbreviatedPath("/opt/x", home: "/Users/a") == "/opt/x")
        #expect(Format.abbreviatedPath("/Users/ab/x", home: "/Users/a") == "/Users/ab/x")
    }

    @Test func memory() {
        #expect(Format.memory(312 * 1_048_576) == "312 MB")
        #expect(Format.memory(1_610_612_736) == "1.5 GB")
    }

    @Test func headerTitle() {
        #expect(Format.headerTitle(count: 0) == "No dev servers running")
        #expect(Format.headerTitle(count: 1) == "1 server running")
        #expect(Format.headerTitle(count: 4) == "4 servers running")
    }

    @Test func devServerURL() {
        var s = DevServer(id: ProcessIdentity(pid: 1, startTime: now), pid: 1, primaryPort: 3001,
                          otherPorts: [], projectName: "p", branch: nil, folder: "/", framework: nil,
                          starter: nil, startTime: now, residentBytes: 0, command: "node",
                          isHTTP: true, stale: nil)
        #expect(s.url == URL(string: "http://localhost:3001"))
        s.isHTTP = false
        #expect(s.url == nil)
    }
}
