# whoisthere — macOS menu bar app for local dev servers

Status: design, awaiting approval (builder check done) · 2026-11-10

## Intent

The user runs many dev servers every day: several apps, git worktrees on different
ports, and Claude Code (and other AI agents) starting servers on yet more ports. Finding
out what is on which port, and killing the stale ones, currently means running `lsof`,
opening another app, or asking an AI. `lsof` shows `node 3001 PID 48213`, which does not
say *which project or worktree* that is.

whoisthere is a small native menu bar app that answers "what dev servers are running,
what do they belong to, and let me kill/open them" in one click.

It will be given away for free (downloaded from a landing page, built later) to other
developers with the same problem, so it must be polished and trustworthy, not just a
personal script.

Reference apps (inspiration only, not to be copied):
- https://github.com/bradystroud/localhost-hq
- https://github.com/almonk/ports

## Goals

- At a glance, see every running **dev server** and what it belongs to: project, git
  branch, worktree, framework, who started it.
- Spot leftovers (servers whose worktree/folder no longer exists) immediately.
- One click to: open in browser, copy URL, see details, kill.
- Native-feeling, light, fast. Something people are happy to leave running.

## Non-goals (v1)

- No "Kill all" button (user explicitly removed it).
- No managing databases/Docker/system services. They are not listed by default.
- No starting/restarting servers, logs, or port reservation.
- No Mac App Store distribution.
- No paid features, accounts, analytics, or network calls.
- The landing page is a separate, later project.

## Anti-goals (would be a failure even if it "works")

- Killing something that is not a dev server the user owns (Postgres, Docker, AirPlay,
  system processes).
- Listing noise: system ports cluttering the list makes the app no better than `lsof`.
- Being heavy: noticeable CPU/battery use from polling, or a slow-to-open menu.
- Mislabeling. Showing the wrong project or branch for a port is worse than showing none.

## Decisions (made with the user)

- **Platform:** native macOS app in **Swift + SwiftUI** (`MenuBarExtra`). The user has not
  built a Mac app before. Code should be straightforward and well-structured to learn from.
- **Distribution:** free, outside the App Store, so **not sandboxed**. It needs to see
  and signal other processes.
- **Row layout ("B with icon actions")**, approved from the mockup
  (`.superpowers/brainstorm/*/content/port-row-v2.html`):
  - Left: port number in monospace.
  - Line 1: `project · branch` + small tags: framework (Next, Vite, …) and a "Claude" tag
    when started by Claude Code.
  - Line 2 (secondary): folder path (worktree path if applicable) · uptime · "you" when
    started from the user's terminal.
  - **Stale servers are visually faded.** A server is stale if either:
    - its folder/worktree no longer exists → line 2: "worktree deleted · up 3 days", or
    - its starting session is gone (terminal tab, Claude session, or editor closed): the
      process has been reparented to launchd (PPID 1) → line 2: "session closed · up 2 days".
    The user's goal: scan the list and kill everything faded without thinking.
  - Right: icon buttons: **Open in browser**, **Copy URL**, **Details**
    (chevron, toggles inline expansion), **Kill** (red). Open/Copy URL are hidden for
    ports that aren't HTTP.
- **Details panel** (inline, below the row): folder, framework (+version if cheap to
  get), started by + how long ago, memory, PID, full command line.
- **Header:** count of running dev servers ("4 servers running"). No Kill all.
- **Only dev servers are listed.**

## Defaults the user approved (proposed by Claude)

- **What counts as a dev server:** a process with a TCP socket in LISTEN state whose
  current working directory is inside the user's home folder (typically a git repo).
  This excludes Homebrew services, Docker, system daemons, AirPlay, etc. without a
  hardcoded list. A setting "Show all listening ports" turns the filter off.
  *Claude's call, refining the above:* on top of the cwd rule, exclude a small deny-list
  of non-dev-server listeners that can still run from a project folder: databases/caches
  (postgres, mysqld, redis-server, mongod), editor/agent internals (VS Code/Cursor
  extension hosts, language servers, Claude Code's IDE bridge), and `--inspect` debugger
  ports. Hidden ones still appear under "Show all listening ports".
- **Menu bar icon:** small icon + number of running dev servers. Dimmed/no number
  when zero.
- **Refresh:** every ~2s while the menu is open; slower (~10–15s) in the background to
  keep the count fresh. Must be cheap.
- **Kill:** no confirmation. SIGTERM, then SIGKILL after ~2s if still alive. The row
  disappears when the port is free.
- **Launch at login:** a toggle (via `SMAppService`).
- **Minimum macOS:** 14 (Sonoma).
- **Shipping:** Developer ID–signed and notarized `.app` (zip or dmg) so users can open
  it without Gatekeeper warnings.
  The user has a paid Apple Developer account.

## Claude's calls (not discussed with the user, builder may revise)

- Working name **whoisthere** (the repo name).
- **Settings** live in a small window opened from a gear/footer item in the menu:
  Launch at login, Show all listening ports, Quit.
- **"Started by" must be remembered**, because once a session closes the parent chain is
  lost. Record it the first time the app sees a server (keyed by PID + process start time,
  persisted across app restarts). Servers first seen already orphaned show no "started by".
- **"Started by"** is determined by walking the parent process chain: an ancestor that is
  Claude Code → "Claude". Terminal/iTerm/Ghostty/etc. → "you". Editor (VS Code, Cursor,
  Zed, Xcode) → the editor's name. Unknown → omitted. Other AI agents (Codex, etc.) can
  be added the same way.
- **Project name:** the git repo's top-level folder name. For a linked worktree, use the
  *main* repo's name (so `shop-web` rather than `shop-web-cart`), with the branch
  distinguishing it. Not in a repo → the folder name.
- **Framework:** inferred from the command line and/or the nearest `package.json`
  (next, vite, astro, remix, nuxt, sveltekit, etc.), plus Python (django, flask,
  uvicorn), Rails, Go, `bun`, `deno`. Unknown → no tag.
- **Kill target:** NOT the whole process group (turbo/concurrently/`pnpm -r` put several
  servers in one group, and an agent/editor may share it). Kill the listener PID and its
  descendants; additionally kill its direct wrapper parent (npm/pnpm/yarn/bun/npx run)
  only if that wrapper has no *other* listening descendants. Never signal a shell,
  terminal, editor, Claude Code, or any process not owned by the user. Verify on real
  setups (npm, pnpm, bun, turbo, concurrently, a server started by Claude Code).
- **HTTP detection** (to decide whether Open/Copy URL show): treat known web frameworks
  and node/bun/deno/python-web processes as HTTP. Optionally a cheap HEAD request to
  `http://localhost:<port>`. URL is `http://localhost:<port>`.
- **One row per server process, not per socket.** The row shows the process's primary
  port (lowest port that looks like HTTP, else lowest). Extra ports (HMR, etc.) are
  listed in the details panel. IPv4/IPv6 duplicates collapse. The header and menu bar
  count = number of server rows ("4 servers running").
- Sort order: by port ascending.
- Process inspection should prefer native APIs (`libproc`: `proc_listpids`,
  `proc_pidinfo`, `proc_pidfdinfo` for sockets and cwd, `sysctl KERN_PROCARGS2` for
  args) over shelling out to `lsof`, for speed. Shelling to `git` for branch is OK,
  but reading `.git/HEAD` (following worktree `.git` files) directly is cheaper.

## Left to the builder

- Project structure (Xcode project vs SwiftPM), architecture, tests.
- Icon choice (SF Symbols are fine), exact spacing, light/dark mode handling (must support
  both).
- Exact polling intervals and caching strategy within the "must be cheap" constraint.
- Packaging script (dmg vs zip), release automation, auto-update (Sparkle) can wait
  until after v1.
