# whoisthere Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app that lists running local dev servers (port, project, branch, framework, who started it, staleness) with open / copy URL / details / kill actions.

**Architecture:** All logic lives in a SwiftPM library `WhoIsThereCore` (pure, unit-tested with `swift test`). Process data comes in through a `ProcessSource` protocol. The live implementation uses `libproc`/`sysctl`, and tests use fakes. A thin SwiftUI app target (`MenuBarExtra`, window style), generated with XcodeGen, depends on the package and only renders `ServerStore` state.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SwiftUI, Observation, Swift Testing, XcodeGen (`/opt/homebrew/bin/xcodegen`), Xcode 26.4, `ServiceManagement` (SMAppService), `notarytool`.

**Spec:** `docs/superpowers/specs/2026-11-10-whoisthere-menubar-design.md`

## Global Constraints

- Minimum macOS 14 (Sonoma). Swift 6 language mode, strict concurrency.
- Not sandboxed (needs to inspect and signal other processes). Hardened runtime ON (required for notarization).
- `LSUIElement = YES`: menu bar only, no Dock icon.
- No network calls, analytics, or accounts. No third-party dependencies.
- No "Kill all" anywhere.
- Only processes owned by the current user are listed or signaled. Never signal a shell, terminal, editor, Claude Code, or PID ≤ 1.
- Kill = SIGTERM, then SIGKILL after 2 s if still alive. No confirmation dialog.
- Refresh: every 2 s while the menu is open, every 12 s in the background.
- Must support light and dark mode. Use system fonts and SF Symbols.
- Bundle id `com.nasanov.whoisthere`, product name `whoisthere`.

## Review Focus

1. **PID reuse:** the PID dies during the 2 s grace period and the OS reuses it for an unrelated process, so SIGKILL hits the wrong process. Expected: nothing is signaled unless the start time still matches. (Test in Task 8.)
2. **Sibling servers under one runner** (`turbo`/`concurrently`/`pnpm -r dev`): killing port 3000 must not kill 3001. (Test in Task 8.)
3. **Deleted cwd:** macOS can still report the old cwd path after the folder is removed, so existence must be checked on disk. The row shows "worktree deleted" using the remembered git info. (Test in Task 6.)
4. **Detached HEAD / linked worktree:** branch shows the 7-char short SHA, and the project name is the *main* repo name. (Test in Task 3.)
5. **Duplicate sockets:** IPv4 + IPv6 on the same port plus an HMR port and a `--inspect` 9229 port must produce one row, with the primary port first, HMR in "other ports", and 9229 dropped. (Tests in Tasks 4 and 6.)

---

## File Structure

```
Package.swift                                   SwiftPM: WhoIsThereCore + tests
project.yml                                     XcodeGen spec for the app target
App/WhoIsThereApp.swift                         @main, MenuBarExtra + Settings scenes
App/MenuBarLabel.swift                          icon + count
App/ServerListView.swift                        header, list, footer
App/ServerRowView.swift                         row + icon buttons + inline details
App/SettingsView.swift                          launch at login, show all ports
App/Info.plist                                  LSUIElement
Sources/WhoIsThereCore/Models.swift             ProcessRecord, ProcessIdentity, GitInfo, Framework, Starter, StaleReason, DevServer
Sources/WhoIsThereCore/Formatting.swift         uptime, path, memory strings
Sources/WhoIsThereCore/GitResolver.swift        read .git without shelling out
Sources/WhoIsThereCore/FrameworkDetector.swift
Sources/WhoIsThereCore/DevServerFilter.swift    which processes/ports count as dev servers
Sources/WhoIsThereCore/StarterDetector.swift
Sources/WhoIsThereCore/ServerMemory.swift       persisted starter + git info per process
Sources/WhoIsThereCore/ServerBuilder.swift      snapshot → [DevServer]
Sources/WhoIsThereCore/LiveProcessSource.swift  libproc/sysctl
Sources/WhoIsThereCore/Killer.swift             KillPlanner + Killer + ProcessSignaler
Sources/WhoIsThereCore/ServerStore.swift        @Observable polling store
Tests/WhoIsThereCoreTests/*.swift               one test file per source file
scripts/release.sh                              archive, sign, notarize, staple, zip
```

---

### Task 1: Scaffold package and app

**Files:**
- Create: `Package.swift`, `project.yml`, `App/WhoIsThereApp.swift`, `App/Info.plist`, `Sources/WhoIsThereCore/Models.swift`, `Tests/WhoIsThereCoreTests/SmokeTests.swift`
- Modify: `.gitignore` (add `build/`, `.build/`, `whoisthere.xcodeproj/`, `.impeccable/`)

**Interfaces:**
- Produces: library product `WhoIsThereCore`. App target `whoisthere` (scheme `whoisthere`) depending on it.

- [ ] **Step 1:** `Package.swift`: `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, library `WhoIsThereCore`, test target `WhoIsThereCoreTests`.
- [ ] **Step 2:** `project.yml`: app target `whoisthere`, platform macOS, deploymentTarget `14.0`, local package dependency `WhoIsThereCore` (path `.`), `PRODUCT_BUNDLE_IDENTIFIER: com.nasanov.whoisthere`, `ENABLE_HARDENED_RUNTIME: YES`, no sandbox entitlement, `INFOPLIST_FILE: App/Info.plist` with `LSUIElement: true`, `SWIFT_VERSION: 6.0`, `CODE_SIGN_STYLE: Automatic`.
- [ ] **Step 3:** `App/WhoIsThereApp.swift`: `MenuBarExtra("whoisthere", systemImage: "network") { Text("whoisthere") }.menuBarExtraStyle(.window)`. Add a smoke test `#expect(WhoIsThereCore.version == "0.1.0")` with `public enum WhoIsThereCore { public static let version = "0.1.0" }` in `Models.swift`.
- [ ] **Step 4: Verify:** `swift test` → 1 test passes. `xcodegen generate && xcodebuild -scheme whoisthere -configuration Debug -derivedDataPath build build` → `BUILD SUCCEEDED`. `open build/Build/Products/Debug/whoisthere.app` shows a menu bar icon and no Dock icon.
- [ ] **Step 5: Commit** `chore: scaffold whoisthere package and menu bar app`

---

### Task 2: Models and formatting

**Files:**
- Modify: `Sources/WhoIsThereCore/Models.swift`
- Create: `Sources/WhoIsThereCore/Formatting.swift`, `Tests/WhoIsThereCoreTests/FormattingTests.swift`

**Interfaces (Produces — every later task uses these exactly):**
```swift
public struct ProcessIdentity: Hashable, Codable, Sendable { public let pid: Int32; public let startTime: Date }
public struct ProcessRecord: Sendable, Equatable {
  public var pid: Int32; public var ppid: Int32; public var uid: UInt32
  public var name: String                 // executable basename, e.g. "node", "zsh", "claude"
  public var executablePath: String?
  public var arguments: [String]          // argv; may be [] if not fetched
  public var cwd: String?
  public var startTime: Date
  public var residentBytes: UInt64
  public var listeningPorts: [UInt16]     // may contain duplicates (v4+v6)
  public var identity: ProcessIdentity { get }
}
public struct GitInfo: Equatable, Codable, Sendable { public var repoName: String; public var branch: String; public var isWorktree: Bool }
public enum Framework: String, Codable, Sendable { case next = "Next", vite = "Vite", astro = "Astro", remix = "Remix", nuxt = "Nuxt", svelteKit = "SvelteKit", angular = "Angular", webpack = "Webpack", django = "Django", flask = "Flask", fastAPI = "FastAPI", rails = "Rails", phoenix = "Phoenix", bun = "Bun", deno = "Deno" }
public enum Starter: Codable, Equatable, Sendable { case claude, terminal, editor(String) }
public enum StaleReason: Equatable, Sendable { case folderDeleted, worktreeDeleted, sessionClosed }
public struct DevServer: Identifiable, Equatable, Sendable {
  public var id: ProcessIdentity; public var pid: Int32
  public var primaryPort: UInt16; public var otherPorts: [UInt16]
  public var projectName: String; public var branch: String?
  public var folder: String; public var framework: Framework?; public var starter: Starter?
  public var startTime: Date; public var residentBytes: UInt64; public var command: String
  public var isHTTP: Bool; public var stale: StaleReason?
  public var url: URL? { get }            // http://localhost:<primaryPort> when isHTTP, else nil
}
public enum Format {
  static func uptime(from: Date, now: Date) -> String
  static func abbreviatedPath(_ path: String, home: String) -> String
  static func memory(_ bytes: UInt64) -> String
  static func headerTitle(count: Int) -> String
}
```

- [ ] **Step 1: Write failing tests** in `FormattingTests.swift`:
  - `uptime`: 30 s → `"<1m"`, 14 min → `"14m"`, 2 h 5 m → `"2h"`, 26 h → `"1 day"`, 3 days 4 h → `"3 days"`.
  - `abbreviatedPath("/Users/a/code/x", home: "/Users/a")` → `"~/code/x"`. `"/opt/x"` unchanged. `"/Users/ab/x"` with home `/Users/a` unchanged (prefix must end on a path boundary).
  - `memory(312 * 1_048_576)` → `"312 MB"`. `memory(1_610_612_736)` → `"1.5 GB"`.
  - `headerTitle(count: 0)` → `"No dev servers running"`, `1` → `"1 server running"`, `4` → `"4 servers running"`.
  - `DevServer.url`: `isHTTP` + port 3001 → `http://localhost:3001`. `isHTTP == false` → `nil`.
- [ ] **Step 2: Run** `swift test --filter FormattingTests` → FAIL (symbols missing).
- [ ] **Step 3: Implement** the models and `Format` exactly as in Interfaces.
- [ ] **Step 4: Run** `swift test --filter FormattingTests` → PASS.
- [ ] **Step 5: Commit** `feat(core): models and formatting`

---

### Task 3: GitResolver

**Files:** Create `Sources/WhoIsThereCore/GitResolver.swift`, `Tests/WhoIsThereCoreTests/GitResolverTests.swift`

**Interfaces:**
- Produces: `public enum GitResolver { public static func resolve(cwd: String) -> GitInfo? }`

Approach: walk up from `cwd` to the first ancestor containing `.git`.
- If `.git` is a **directory**: repoName = that ancestor's folder name, HEAD = `.git/HEAD`, `isWorktree = false`.
- If `.git` is a **file** (`gitdir: <path>`, relative paths resolved against the ancestor): HEAD = `<gitdir>/HEAD`. The common dir comes from `<gitdir>/commondir` (relative to gitdir). repoName = the folder name of the common dir's parent. `isWorktree = true`.
- HEAD `ref: refs/heads/<name>` → branch `<name>` (keeps slashes). Otherwise the first 7 chars of the SHA.
- Return `nil` if no `.git` is found or files can't be read. No `git` subprocess.

- [ ] **Step 1: Write failing tests.** Build fixtures in a temp dir. Write the files directly; don't run git:
  - `plainRepo`: `/tmp/X/shop-web/.git/HEAD` = `ref: refs/heads/main\n`, cwd `/tmp/X/shop-web/apps/web` → `GitInfo(repoName: "shop-web", branch: "main", isWorktree: false)`.
  - `linkedWorktree`: main at `/tmp/X/shop-web/.git/worktrees/cart/{HEAD = "ref: refs/heads/feat/cart", commondir = "../.."}`, worktree `/tmp/X/wt/shop-web-cart/.git` = `gitdir: /tmp/X/shop-web/.git/worktrees/cart` → `("shop-web", "feat/cart", true)`.
  - `detachedHead`: HEAD = `a1b2c3d4e5f6...` → branch `"a1b2c3d"`.
  - `notARepo` → `nil`. `missingCwd` (path doesn't exist) → `nil`.
- [ ] **Step 2: Run** `swift test --filter GitResolverTests` → FAIL.
- [ ] **Step 3: Implement** `GitResolver.resolve`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): resolve git repo, branch, worktree from .git`

---

### Task 4: FrameworkDetector and DevServerFilter

**Files:** Create `FrameworkDetector.swift`, `DevServerFilter.swift`, and tests for each.

**Interfaces:**
```swift
public enum FrameworkDetector { public static func detect(arguments: [String], packageJSON: Data?) -> Framework? }
public enum DevServerFilter {
  public static func includes(_ p: ProcessRecord, home: String, currentUID: UInt32, showAll: Bool) -> Bool
  public static func visiblePorts(_ p: ProcessRecord) -> [UInt16]   // deduped, ascending, inspector ports removed
  public static func looksHTTP(_ p: ProcessRecord, framework: Framework?) -> Bool
}
```

Rules:
- **FrameworkDetector**, first match wins. Arguments joined by spaces, matched case-insensitively:
  - `next` → `.next`, `vite` → `.vite`, `astro` → `.astro`, `remix` → `.remix`, `nuxt` → `.nuxt`, `svelte-kit` → `.svelteKit`, `ng serve` → `.angular`, `webpack` → `.webpack`, `manage.py runserver` → `.django`, `flask` → `.flask`, `uvicorn` → `.fastAPI`, `rails`/`puma` → `.rails`, `phx.server` → `.phoenix`.
  - Otherwise, the `package.json` dependency keys `next`, `vite`, `astro`, `@remix-run/dev`, `nuxt`, `@sveltejs/kit` map the same way.
  - Otherwise, argv[0] basename `bun` → `.bun`, `deno` → `.deno`. Else `nil`.
  - Match on path components or words, so `/Users/a/nextcloud/server.js` does NOT match `next`.
- **includes:**
  - `showAll` → owned by `currentUID` and has ≥1 port.
  - Else all of the following must hold: owned by `currentUID`; `visiblePorts` non-empty; `cwd` starts with `home + "/"`; `name` not in deny-list `["postgres", "mysqld", "redis-server", "mongod", "claude"]`; `executablePath` doesn't contain `.app/Contents/` (editor, Electron and app internals).
- **visiblePorts:** dedupe and sort. If any argument starts with `--inspect`, drop 9229 and 9230 plus any port given as `--inspect=<host:>port` / `--inspect-brk=…`.
- **looksHTTP:** `framework != nil` or `name` ∈ `["node", "bun", "deno", "python", "python3", "ruby", "php", "go", "java"]`.

- [ ] **Step 1: Write failing tests:**
  - `detect(["node", "/p/node_modules/.bin/next", "dev"], nil)` → `.next`.
  - `detect(["node", "/p/node_modules/vite/bin/vite.js"], nil)` → `.vite`.
  - `detect(["node", "server.js"], packageJSON with "astro")` → `.astro`.
  - `detect(["node", "/Users/a/nextcloud/server.js"], nil)` → `nil`.
  - `detect(["bun", "run", "index.ts"], nil)` → `.bun`.
  - `includes`:
    - node, cwd `~/code/x`, port 3000 → true
    - postgres, cwd `~/code/x` → false
    - cwd `/` → false
    - other uid → false
    - path `/Applications/Cursor.app/Contents/…` → false
    - postgres with showAll → true
  - `visiblePorts`: node `--inspect` with ports `[3000, 3000, 24678, 9229]` → `[3000, 24678]`.
- [ ] **Step 2: Run** `swift test --filter "FrameworkDetectorTests|DevServerFilterTests"` → FAIL.
- [ ] **Step 3: Implement** both.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): framework detection and dev-server filter`

---

### Task 5: StarterDetector and ServerMemory

**Files:** Create `StarterDetector.swift`, `ServerMemory.swift`, and tests for each.

**Interfaces:**
```swift
public enum StarterDetector { public static func detect(ancestors: [ProcessRecord]) -> Starter? }  // nearest parent first
public struct Remembered: Codable, Equatable, Sendable { public var starter: Starter?; public var git: GitInfo? }
public final class ServerMemory: @unchecked Sendable {   // guarded by an internal lock
  public init(fileURL: URL)                              // loads if present; corrupt file → start empty
  public func recall(_ id: ProcessIdentity) -> Remembered?
  public func remember(_ id: ProcessIdentity, _ value: Remembered)
  public func prune(keeping: Set<ProcessIdentity>)
  public func save() throws                              // atomic write; only writes if changed
}
```

Rules:
- Walk ancestors nearest-first. The first match wins:
  - name `claude`, or any argument containing `claude-code` → `.claude`
  - name ∈ `["Terminal", "iTerm2", "ghostty", "Ghostty", "WezTerm", "wezterm-gui", "alacritty", "kitty", "Warp", "stable", "tmux"]` → `.terminal`
  - executable path contains `Visual Studio Code.app` → `.editor("VS Code")`, `Cursor.app` → `.editor("Cursor")`, `Zed.app` → `.editor("Zed")`, `Xcode.app` → `.editor("Xcode")`
- Stop at PID 1 and return `nil`.
- Memory file: `~/Library/Application Support/whoisthere/memory.json` (the app passes this in; tests use a temp file).

- [ ] **Step 1: Write failing tests:**
  - ancestors `[zsh, claude, zsh, Ghostty]` → `.claude`
  - `[zsh, login, Terminal]` → `.terminal`
  - `[zsh, Code Helper (path …/Visual Studio Code.app/…)]` → `.editor("VS Code")`
  - `[launchd(pid 1)]` → `nil`
  - Memory round-trip: remember → save → new instance → recall equal.
  - Prune removes the identities that weren't kept.
  - A corrupt file loads empty without throwing.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): starter detection and persistent server memory`

---

### Task 6: ServerBuilder

**Files:** Create `ServerBuilder.swift`, `Tests/WhoIsThereCoreTests/ServerBuilderTests.swift`

**Interfaces:**
```swift
public struct ServerBuilder: Sendable {
  public init(home: String, currentUID: UInt32,
              fileExists: @Sendable @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
              resolveGit: @Sendable @escaping (String) -> GitInfo? = GitResolver.resolve,
              readPackageJSON: @Sendable @escaping (String) -> Data? = { /* nearest package.json walking up from cwd, stopping at home */ })
  public func build(snapshot: [ProcessRecord], showAll: Bool, memory: ServerMemory) -> [DevServer]
}
```

For each record where `DevServerFilter.includes`:
- ports = `visiblePorts`. **primaryPort** = the lowest port if `looksHTTP`, otherwise the lowest. `otherPorts` = the rest.
- Ancestors come from the snapshot's ppid chain. The starter is `memory.recall(id)?.starter`. If nothing is remembered, call `StarterDetector.detect`. On the first sighting, record `Remembered(starter, git)` and never overwrite it later.
- **folderExists** = `cwd != nil && fileExists(cwd)`. Git = `resolveGit(cwd)` if the folder exists, else the remembered git.
- **projectName** = `git?.repoName` ?? the last path component of cwd. **branch** = `git?.branch`.
- **stale:** folder missing → `.worktreeDeleted` if the remembered/derived git has `isWorktree`, else `.folderDeleted`. Else `ppid == 1` → `.sessionClosed`. Else `nil`.
- **command** = arguments joined by `" "` (fallback: `name`).
- Sort by `primaryPort` ascending. After building, call `memory.prune(keeping:)` with the identities still alive in the snapshot.

- [ ] **Step 1: Write failing tests** (fake closures, temp `ServerMemory`):
  - `groupsPorts`: one node record with ports `[5173, 5173, 24678]` → 1 server, primary 5173, others `[24678]`.
  - `claudeStarter`: parent chain zsh → claude → server starter `.claude`, remembered.
  - `starterSurvivesOrphaning`: build once with the parent chain, then again with `ppid = 1` and the parents gone → starter still `.claude`, stale `.sessionClosed`.
  - `deletedWorktree`: first build with git `isWorktree: true`, then `fileExists` returns false → stale `.worktreeDeleted`, projectName and branch still from memory.
  - `deletedPlainFolder` (never seen before) → `.folderDeleted`, projectName = last path component.
  - `sortedByPort`: ports 5173, 3000, 3001 → order 3000, 3001, 5173.
  - `nonHTTP`: name `erl` with no framework → `url == nil`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): build dev server rows from process snapshot`

---

### Task 7: LiveProcessSource

**Files:** Create `LiveProcessSource.swift`, `Tests/WhoIsThereCoreTests/LiveProcessSourceTests.swift`

**Interfaces:**
```swift
public protocol ProcessSource: Sendable { func snapshot() throws -> [ProcessRecord] }
public struct LiveProcessSource: ProcessSource { public init(); public func snapshot() throws -> [ProcessRecord] }
```

Approach (`import Darwin`, no `lsof`):
- `proc_listpids(PROC_ALL_PIDS…)`. Per PID, `proc_pidinfo(PROC_PIDTBSDINFO)` gives ppid, uid, comm and start time (`pbi_start_tvsec/usec`).
- Keep **all** processes in the snapshot, because ancestors are needed. For uid == current user only:
  - list fds via `PROC_PIDLISTFDS`
  - for `PROX_FDTYPE_SOCKET`, call `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`
  - keep TCP sockets (`soi_kind == SOCKINFO_TCP`) with `tcpsi_state == TSI_S_LISTEN`
  - read the local port from `insi_lport` and convert with `UInt16(bigEndian:)`
- Fetch `cwd` (`PROC_PIDVNODEPATHINFO`), `arguments` (`sysctl KERN_PROCARGS2`) and `residentBytes` (`PROC_PIDTASKINFO`) only for processes with listening ports and for their ancestors. Fetch `executablePath` via `proc_pidpath` and `name` (basename of the path, falling back to comm) for those same processes.
- Any per-PID call that fails because the process vanished → skip that record silently. Never throw for that.

- [ ] **Step 1: Write failing integration test** `findsSpawnedServer`:
  - Create temp dir `D`.
  - Spawn `/usr/bin/python3 -m http.server 0 --bind 127.0.0.1` with cwd `D`. Read the port from stdout (`Serving HTTP on … port N`).
  - Snapshot. Expect a record with that pid, `listeningPorts` containing N, `cwd` resolving to `D` (compare `realpath`), and `arguments` containing `"http.server"`.
  - Its parent chain reaches the test runner's pid. Terminate the child in `defer`.
- [ ] **Step 2: Run** `swift test --filter LiveProcessSourceTests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS. Also print `snapshot().filter { !$0.listeningPorts.isEmpty }.count` once and time it: it must run in under 100 ms on this machine (note the time in the commit message).
- [ ] **Step 5: Commit** `feat(core): libproc-based live process source`

---

### Task 8: KillPlanner and Killer

**Files:** Create `Killer.swift`, `Tests/WhoIsThereCoreTests/KillerTests.swift`

**Interfaces:**
```swift
public enum KillPlanner {
  public static func targets(for server: ProcessIdentity, snapshot: [ProcessRecord], currentUID: UInt32) -> [ProcessIdentity]
}
public protocol ProcessSignaler: Sendable {
  func startTime(of pid: Int32) -> Date?          // nil if not running
  func send(_ signal: Int32, to pid: Int32)
}
public struct DarwinSignaler: ProcessSignaler { public init() }   // proc_pidinfo + kill(2)
public struct Killer: Sendable {
  public init(signaler: ProcessSignaler = DarwinSignaler(), grace: Duration = .seconds(2), pollInterval: Duration = .milliseconds(100))
  public func terminate(_ targets: [ProcessIdentity]) async
}
```

Rules:
- **Targets** = the server process + all its descendants (via ppid). Also add the direct parent **only if** it is a package runner and none of its other descendants are listening:
  - package runner: argv[0] basename ∈ `["npm", "pnpm", "yarn", "npx", "pnpx"]`; or any argument ends with `npm-cli.js`, `pnpm.cjs` or `yarn.js`; or (basename ∈ `["bun", "deno"]` and args contain `run` or `task`)
- Always exclude:
  - pid ≤ 1
  - uid ≠ current
  - name ∈ shells `["zsh", "bash", "sh", "fish", "login", "tmux"]`
  - anything `StarterDetector` would classify as a starter (Claude, terminals, editors)
- **Killer:**
  - Send SIGTERM to each target whose current `startTime` equals the identity's.
  - Poll until all are gone or the grace period ends.
  - Then SIGKILL the survivors, again only if their start time still matches.

- [ ] **Step 1: Write failing tests:**
  - `killsServerAndChildren`: server 100 with child 101 → targets {100, 101}.
  - `includesNpmWrapper`: parent 90 `npm run dev` → includes 90.
  - `spareSiblingsUnderRunner`: parent 80 `node …/concurrently` (not a package runner) with children 100 (port 3000) and 200 (port 3001). Killing 100 excludes 80 and 200. Also, parent `npm` with two listening children → npm excluded.
  - `neverKillsClaudeOrShell`: a child of the server named `claude` or `zsh` is excluded.
  - `pidReuseNotSignaled` (fake signaler): SIGTERM sent, then the fake reports a different `startTime` → no SIGKILL sent.
  - `escalatesToSigkill` (fake): process stays alive → SIGTERM then SIGKILL after the grace period (use `grace: .milliseconds(50)`).
  - `realProcess` (integration): spawn `python3 -c "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"`, terminate with `DarwinSignaler` and `grace: .milliseconds(300)` → the process is gone afterward.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): safe kill planning and graceful termination`

---

### Task 9: ServerStore

**Files:** Create `ServerStore.swift`, `Tests/WhoIsThereCoreTests/ServerStoreTests.swift`

**Interfaces:**
```swift
@MainActor @Observable public final class ServerStore {
  public private(set) var servers: [DevServer]
  public var showAll: Bool          // persisted by the app via @AppStorage("showAllPorts"); setting it triggers refresh()
  public var isMenuOpen: Bool       // switches polling between 2 s and 12 s
  public var pollInterval: Duration { get }
  public init(source: ProcessSource, builder: ServerBuilder, memory: ServerMemory, killer: Killer, currentUID: UInt32)
  public func start()               // begins the polling loop (single Task; restarted when the interval changes)
  public func stop()
  public func refresh() async       // snapshot off the main actor, build, assign, memory.save()
  public func kill(_ server: DevServer) async   // plan from a fresh snapshot, terminate, then refresh()
}
```

- [ ] **Step 1: Write failing tests** with a fake `ProcessSource` and fake signaler:
  - `refreshPopulates`: the fake returns one dev server → `servers.count == 1`.
  - `intervalFollowsMenu`: `pollInterval == .seconds(12)`. After `isMenuOpen = true` → `.seconds(2)`.
  - `killRemovesRow`: after `kill`, the fake source no longer returns the process → `servers` is empty, and the fake signaler received SIGTERM for that pid.
  - `snapshotErrorKeepsLastList`: the source throws → `servers` is unchanged.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): observable polling server store`

---

### Task 10: Menu bar UI, settings, launch at login

**Files:** Create `App/MenuBarLabel.swift`, `App/ServerListView.swift`, `App/ServerRowView.swift`, `App/SettingsView.swift`. Modify `App/WhoIsThereApp.swift`.

**Interfaces:**
- Consumes: `ServerStore`, `DevServer`, `Format`. The app constructs the store with `LiveProcessSource()`, `ServerBuilder(home: NSHomeDirectory(), currentUID: getuid())`, `ServerMemory(fileURL: ~/Library/Application Support/whoisthere/memory.json)` and `Killer()`.

Layout, matching the approved mockup `.superpowers/brainstorm/*/content/port-row-v2.html`. The panel is about 420 pt wide.
- **Menu bar label:** SF Symbol `network` plus the count. When the count is 0, show the symbol alone at secondary opacity.
- **Header:** `Format.headerTitle(count:)`. No Kill all.
- **Row:**
  - Port in monospaced semibold on the left.
  - Line 1: `projectName · branch`, a framework tag, and a `Claude` tag (warm tint) when `starter == .claude`.
  - Line 2 (secondary, 11 pt), joined with ` · `:
    - stale → `"worktree deleted"`, `"folder deleted"` or `"session closed"`
    - otherwise → `Format.abbreviatedPath(folder)`
    - then `"up " + uptime`
    - then `"you"` for `.terminal`, or the editor name for `.editor`
  - Stale rows render at 0.55 opacity.
  - Right side: icon buttons with tooltips:
    - `arrow.up.right.square` Open in browser (only when `url != nil`)
    - `doc.on.doc` Copy URL (only when `url != nil`)
    - `chevron.down` / `chevron.up` Details
    - `xmark.circle` Kill, in red
- **Details** (inline, below the row, white/grouped background):
  - Folder (full path)
  - Framework
  - Started by + `Format.uptime` + " ago"
  - Memory · PID
  - Command (monospaced, selectable)
  - Other ports (when non-empty)
- **Empty state:** "No dev servers running".
- **Footer:** Settings… (`SettingsLink`) and Quit.
- `isMenuOpen` is set from `.onAppear`/`.onDisappear` of the panel content.
- **Settings window:** "Launch at login" toggle backed by `SMAppService.mainApp` (register/unregister; read `status` on appear) and "Show all listening ports" (`@AppStorage("showAllPorts")` → `store.showAll`).

- [ ] **Step 1: Build:** `xcodegen generate && xcodebuild -scheme whoisthere -derivedDataPath build build` → `BUILD SUCCEEDED`.
- [ ] **Step 2: Manual verification** (use the `run` skill to launch). In two temp git repos, one with a linked worktree on branch `feat/x`, start `python3 -m http.server 3000` and `python3 -m http.server 3001`. Confirm:
  - The menu bar shows `2`.
  - Rows show the correct repo, branch and folder.
  - Open launches the browser at the right port, and Copy puts `http://localhost:3001` on the clipboard.
  - Details expands and collapses.
  - Kill removes the row within about 2 s.
  - Close the terminal tab of a server started with `nohup … &`: that row fades with "session closed".
  - Delete a worktree folder while its server runs: the row shows "worktree deleted".
  - Check light and dark mode.
- [ ] **Step 3: Commit** `feat(app): menu bar list, row actions, details, settings`

---

### Task 11: Signed, notarized release build

**Files:** Create `scripts/release.sh`. Modify `README.md` (what it is, how to build, how to release).

`release.sh` requires the env vars `DEVELOPMENT_TEAM` and `NOTARY_PROFILE` (a keychain profile created once with `xcrun notarytool store-credentials`). Steps:
1. `xcodegen generate`
2. `xcodebuild archive -scheme whoisthere -configuration Release -archivePath build/whoisthere.xcarchive DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Developer ID Application"`
3. `xcodebuild -exportArchive` with an inline `ExportOptions.plist` (`method: developer-id`)
4. `ditto -c -k --keepParent` → `build/whoisthere.zip`
5. `xcrun notarytool submit … --keychain-profile $NOTARY_PROFILE --wait`
6. `xcrun stapler staple` the `.app`
7. Re-zip → `build/whoisthere-<version>.zip`

The script exits non-zero on any failure (`set -euo pipefail`).

- [ ] **Step 1:** Write the script and README section.
- [ ] **Step 2: Verify** (needs the user's Apple Developer credentials; ask the user to run the one-time `store-credentials` themselves): `DEVELOPMENT_TEAM=… NOTARY_PROFILE=… scripts/release.sh` → notarization `status: Accepted`. Then `spctl -a -vv build/export/whoisthere.app` → `accepted, source=Notarized Developer ID`.
- [ ] **Step 3: Commit** `chore: release script for signed, notarized builds`
