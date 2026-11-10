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

    @Test func directoryNamesDoNotTagFramework() {
        #expect(FrameworkDetector.detect(arguments: ["node", "/Users/me/vite/server.js"], packageJSON: nil) == nil)
        #expect(FrameworkDetector.detect(arguments: ["python3", "/Users/me/flask/app.py"], packageJSON: nil) == nil)
        #expect(FrameworkDetector.detect(arguments: ["/Users/me/next/venv/bin/python3", "-m", "http.server"],
                                         packageJSON: nil) == nil)
        #expect(FrameworkDetector.detect(arguments: ["node", "/Users/me/rails/manage.py", "runserver"],
                                         packageJSON: nil) == .django)
    }

    @Test func nextServerProcessTitle() {
        // node rewrites argv via process.title: KERN_PROCARGS2 shows ["next-server (v16.1.6)", ""].
        #expect(FrameworkDetector.detect(arguments: ["next-server (v16.1.6)", ""], packageJSON: nil) == .next)
    }

    @Test func jsRuntimeDetection() {
        func p(_ name: String, _ args: [String]) -> ProcessRecord {
            ProcessRecord(pid: 1, ppid: 0, uid: 501, name: name, executablePath: nil, arguments: args,
                          cwd: nil, startTime: Date(timeIntervalSince1970: 0), residentBytes: 0, listeningPorts: [])
        }
        #expect(FrameworkDetector.isJSRuntime(p("node", ["next-server (v16.1.6)", ""])))
        #expect(FrameworkDetector.isJSRuntime(p("bun", ["bun", "run", "dev"])))
        #expect(FrameworkDetector.isJSRuntime(p("x", ["/Users/me/.deno/bin/deno", "task", "dev"])))
        #expect(!FrameworkDetector.isJSRuntime(p("Python", ["/opt/homebrew/.../Python", "-m", "http.server"])))
        #expect(!FrameworkDetector.isJSRuntime(p("ruby", ["ruby", "bin/rails", "s"])))
    }
}
