import Testing
import Foundation
@testable import WhoIsThereCore

struct FrameworkDetectorTests {
    @Test func detectsNextFromBin() {
        #expect(FrameworkDetector.detect(arguments: ["node", "/p/node_modules/.bin/next", "dev"], packageJSON: nil) == .next)
    }

    @Test func detectsViteFromScriptBasename() {
        #expect(FrameworkDetector.detect(arguments: ["node", "/p/node_modules/vite/bin/vite.js"], packageJSON: nil) == .vite)
    }

    @Test func detectsFromPackageJSON() {
        let json = Data(#"{"dependencies":{"astro":"^4"}}"#.utf8)
        #expect(FrameworkDetector.detect(arguments: ["node", "server.js"], packageJSON: json) == .astro)
    }

    @Test func invalidPackageJSONIgnored() {
        #expect(FrameworkDetector.detect(arguments: ["node", "server.js"], packageJSON: Data("nope".utf8)) == nil)
    }

    @Test func doesNotMatchSubstring() {
        #expect(FrameworkDetector.detect(arguments: ["node", "/Users/a/nextcloud/server.js"], packageJSON: nil) == nil)
    }

    @Test func detectsBun() {
        #expect(FrameworkDetector.detect(arguments: ["bun", "run", "index.ts"], packageJSON: nil) == .bun)
    }

    @Test func detectsMultiWordPatterns() {
        #expect(FrameworkDetector.detect(arguments: ["python", "manage.py", "runserver"], packageJSON: nil) == .django)
        #expect(FrameworkDetector.detect(arguments: ["node", "ng", "serve"], packageJSON: nil) == .angular)
        #expect(FrameworkDetector.detect(arguments: ["mix", "phx.server"], packageJSON: nil) == .phoenix)
    }
}
