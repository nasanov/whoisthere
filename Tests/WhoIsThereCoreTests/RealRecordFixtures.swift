import Foundation
import Testing
@testable import WhoIsThereCore

/// ProcessRecords as `LiveProcessSource` produced them on a real machine (macOS 26,
/// 2026-11-10): native Claude Code under T3 Code, `npm run dev` chains for vite and
/// next (note node's process.title argv rewriting), and Homebrew/Xcode Python servers.
/// Only start times and memory are normalized.
private enum Real {
    static let home = "/Users/nasanov"
    static let uid: UInt32 = 501
    static let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    static func rec(_ pid: Int32, _ ppid: Int32, _ name: String, _ path: String?, _ args: [String],
                    cwd: String?, ports: [UInt16] = []) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, uid: uid, name: name, executablePath: path, arguments: args,
                      cwd: cwd, startTime: t0, residentBytes: 50_000_000, listeningPorts: ports)
    }

    static let t3App = "/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)"
    static let node = "/Users/nasanov/.nvm/versions/node/v20.19.6/bin/node"
    static let edc = "/Users/nasanov/Desktop/projects/edc.deals"
    static let regenics = "/Users/nasanov/Desktop/regenics/regenics-frontend/.claude/worktrees/agent-a341b201c277784b5"
    static let portfolioPrototypes = "/Users/nasanov/Desktop/portfolio/.claude/prototypes"

    static let t3Main = rec(28098, 1, "T3 Code (Beta)", t3App, [t3App], cwd: "/")
    static let t3Server = rec(28485, 28098, "T3 Code (Beta)", t3App, [
        t3App, "--require",
        "/Applications/T3 Code (Beta).app/Contents/Resources/app.asar/apps/desktop/dist-electron/compileCache.cjs",
        "/Applications/T3 Code (Beta).app/Contents/Resources/app.asar/apps/server/dist/bin.mjs",
        "--bootstrap-fd", "3",
    ], cwd: home, ports: [3773])

    // Native Claude Code: the executable's basename is its version number.
    static let claude = rec(77285, 28485, "2.1.306", "/Users/nasanov/.local/share/claude/versions/2.1.306", [
        "claude", "--output-format", "stream-json", "--verbose", "--input-format", "stream-json",
        "--model", "claude-opus-5-5", "--permission-prompt-tool", "stdio",
        "--add-dir", "/Users/nasanov/.t3/projects/whoisthere",
    ], cwd: "/Users/nasanov/.t3/projects/whoisthere")
    static let claudeMCP = rec(77306, 77285, "node", node, ["npm exec chrome-devtools-mcp@latest", "", ""],
                               cwd: "/Users/nasanov/.t3/projects/whoisthere")

    // T3 Code terminal: zsh -> npm run dev -> node .bin/next dev -> next-server -> postcss.
    static let nextShell = rec(91932, 28485, "zsh", "/bin/zsh", ["/bin/zsh", "-o", "nopromptsp"], cwd: edc)
    static let nextNpm = rec(42654, 91932, "node", node, ["npm run dev", "", "", ""], cwd: edc)
    static let nextDev = rec(42670, 42654, "node", node, ["node", edc + "/node_modules/.bin/next", "dev"], cwd: edc)
    static let nextServer = rec(42671, 42670, "node", node, ["next-server (v16.1.6)", ""], cwd: edc, ports: [3000])
    static let nextPostcss = rec(42759, 42671, "node", node,
                                 ["node", edc + "/.next/dev/build/postcss.js", "61090"], cwd: edc)

    // T3 Code terminal: zsh -> npm run dev -> node .bin/vite -> esbuild.
    static let viteShell = rec(3628, 28485, "zsh", "/bin/zsh", ["/bin/zsh", "-o", "nopromptsp"], cwd: regenics)
    static let viteNpm = rec(4423, 3628, "node", node, ["npm run dev", "", "", ""], cwd: regenics)
    static let vite = rec(4442, 4423, "node", node, ["node", regenics + "/node_modules/.bin/vite"],
                          cwd: regenics, ports: [5174])
    static let esbuild = rec(4444, 4442, "esbuild", regenics + "/node_modules/@esbuild/darwin-arm64/bin/esbuild",
                             [regenics + "/node_modules/@esbuild/darwin-arm64/bin/esbuild", "--service=0.25.10", "--ping"],
                             cwd: regenics)

    // Orphaned Homebrew Python static server inside a JS project (whose package.json has next).
    static let brewPythonPath = "/opt/homebrew/Cellar/python@3.14/3.14.6/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"
    static let brewPython = rec(8748, 1, "Python", brewPythonPath,
                                [brewPythonPath, "-m", "http.server", "4719"],
                                cwd: portfolioPrototypes, ports: [4719])

    // Xcode's bundled Python, started from Terminal.
    static let xcodePythonPath = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
    static let terminal = rec(600, 1, "Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
                              ["/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"], cwd: "/")
    static let login = rec(601, 600, "login", "/usr/bin/login", ["login", "-pf", "nasanov"], cwd: home)
    static let terminalShell = rec(602, 601, "zsh", "/bin/zsh", ["-zsh"], cwd: home + "/code/site")
    static let xcodePython = rec(603, 602, "Python", xcodePythonPath,
                                 ["/usr/bin/python3", "-m", "http.server", "8000"],
                                 cwd: home + "/code/site", ports: [8000])

    // A vite server Claude Code started through a shell.
    static let claudeShell = rec(700, 77285, "zsh", "/bin/zsh", ["/bin/zsh", "-c", "npm run dev"], cwd: regenics)
    static let claudeNpm = rec(701, 700, "node", node, ["npm run dev", "", "", ""], cwd: regenics)
    static let claudeVite = rec(702, 701, "node", node, ["node", regenics + "/node_modules/.bin/vite", "--port", "5175"],
                                cwd: regenics, ports: [5175])

    static let snapshot: [ProcessRecord] = [
        t3Main, t3Server, claude, claudeMCP,
        nextShell, nextNpm, nextDev, nextServer, nextPostcss,
        viteShell, viteNpm, vite, esbuild,
        brewPython, terminal, login, terminalShell, xcodePython,
        claudeShell, claudeNpm, claudeVite,
    ]

    static let byPID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.pid, $0) })

    static func ancestors(_ p: ProcessRecord) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var current = p
        while let parent = byPID[current.ppid] {
            result.append(parent)
            current = parent
        }
        return result
    }

    static func targets(_ p: ProcessRecord) -> [Int32] {
        KillPlanner.targets(for: p.identity, snapshot: snapshot, currentUID: uid).map(\.pid).sorted()
    }

    static let nextPackageJSON = Data(#"{"dependencies":{"next":"16.1.6","react":"19"}}"#.utf8)
    static let vitePackageJSON = Data(#"{"devDependencies":{"vite":"7"}}"#.utf8)
}

@Suite struct RealRecordFixtures {
    @Test func starters() {
        #expect(StarterDetector.classify(Real.claude) == .claude)
        #expect(StarterDetector.classify(Real.t3Server) == .editor("T3 Code"))
        #expect(StarterDetector.detect(ancestors: Real.ancestors(Real.nextServer)) == .editor("T3 Code"))
        #expect(StarterDetector.detect(ancestors: Real.ancestors(Real.vite)) == .editor("T3 Code"))
        #expect(StarterDetector.detect(ancestors: Real.ancestors(Real.claudeVite)) == .claude)
        #expect(StarterDetector.detect(ancestors: Real.ancestors(Real.xcodePython)) == .terminal)
        #expect(StarterDetector.detect(ancestors: Real.ancestors(Real.brewPython)) == nil)
        // Bundled runtimes are servers, not editors.
        #expect(StarterDetector.classify(Real.xcodePython) == nil)
        #expect(StarterDetector.classify(Real.brewPython) == nil)
    }

    @Test func killPlans() {
        #expect(Real.targets(Real.nextServer) == [42654, 42670, 42671, 42759])
        #expect(Real.targets(Real.vite) == [4423, 4442, 4444])
        #expect(Real.targets(Real.claudeVite) == [701, 702]) // shell and Claude spared
        #expect(Real.targets(Real.brewPython) == [8748])
        #expect(Real.targets(Real.xcodePython) == [603])
        #expect(Real.targets(Real.claude).isEmpty)
        #expect(Real.targets(Real.t3Server).isEmpty)
    }

    @Test func frameworks() {
        #expect(FrameworkDetector.detect(arguments: Real.nextServer.arguments, packageJSON: Real.nextPackageJSON) == .next)
        #expect(FrameworkDetector.detect(arguments: Real.nextServer.arguments, packageJSON: nil) == .next)
        #expect(FrameworkDetector.detect(arguments: Real.vite.arguments, packageJSON: nil) == .vite)
        #expect(FrameworkDetector.detect(arguments: Real.brewPython.arguments, packageJSON: nil) == nil)
        #expect(FrameworkDetector.detect(arguments: Real.xcodePython.arguments, packageJSON: nil) == nil)
        #expect(!FrameworkDetector.isJSRuntime(Real.brewPython))
        #expect(FrameworkDetector.isJSRuntime(Real.nextServer))
    }

    @Test func builtRows() {
        let builder = ServerBuilder(
            home: Real.home, currentUID: Real.uid, fileExists: { _ in true },
            resolveGit: { _ in nil },
            readPackageJSON: { cwd in
                // Every folder here lives in a JS project; the portfolio one has next.
                cwd.hasPrefix(Real.regenics) ? Real.vitePackageJSON : Real.nextPackageJSON
            })
        let memory = ServerMemory(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("whoisthere-\(UUID().uuidString)/memory.json"))
        let rows = builder.build(snapshot: Real.snapshot, showAll: false, memory: memory)

        #expect(rows.map(\.primaryPort) == [3000, 4719, 5174, 5175, 8000])
        let byPort = Dictionary(uniqueKeysWithValues: rows.map { ($0.primaryPort, $0) })
        #expect(byPort[3000]?.framework == .next)
        #expect(byPort[3000]?.starter == .editor("T3 Code"))
        #expect(byPort[3000]?.projectName == "edc.deals")
        #expect(byPort[4719]?.framework == nil)
        #expect(byPort[4719]?.stale == .sessionClosed)
        #expect(byPort[4719]?.isHTTP == true)
        #expect(byPort[5174]?.framework == .vite)
        #expect(byPort[5175]?.starter == .claude)
        #expect(byPort[8000]?.starter == .terminal)
        #expect(byPort[8000]?.framework == nil)
    }
}
