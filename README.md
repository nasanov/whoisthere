<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="whoisthere icon">
</p>

<h1 align="center">whoisthere</h1>

<p align="center">
  <b>See which dev servers are running on your Mac, and stop them in one click.</b><br>
  A tiny menu bar app for people who run too many <code>npm run dev</code>s.
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/menu-dark.png">
    <img src="docs/screenshots/menu-light.png" width="820" alt="whoisthere menu listing six dev servers with their project, branch and framework">
  </picture>
</p>

## Why

Between your own projects, git worktrees, and the servers Claude Code starts for you, ports fill up fast. `lsof -i :3000` tells you `node 48213`, which doesn't say *which project* that is. whoisthere does.

## What it shows

- **Every dev server, by project.** Port, project name and git branch (worktrees included), framework, and how long it's been up.
- **Who started it.** You in a terminal, Claude Code, or your editor (VS Code, Cursor, Zed, Xcode, JetBrains…).
- **Leftovers, faded.** Servers whose worktree or folder was deleted, or whose terminal was closed, are dimmed so you can clean them up without thinking.
- **One-click actions.** Open in browser, copy the URL, see details, or stop it.
- **Only dev servers.** Databases, Docker, AirPlay and system services stay out of the list (there's a setting to show everything).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/menu-details-dark.png">
    <img src="docs/screenshots/menu-details-light.png" width="820" alt="A server row expanded to show its folder, framework, who started it, memory, PID and command">
  </picture>
</p>

## Stopping a server

Stop sends the server a polite `SIGTERM`, then `SIGKILL` if it's still there after 2 seconds. It also stops the server's child processes and its `npm`/`pnpm`/`yarn`/`bun` wrapper, but never your shell, terminal, editor, Claude Code, or anything owned by another user.

## Private by design

Everything is read locally from macOS process APIs. No network calls, no analytics, no accounts.

## Requirements

macOS 14 (Sonoma) or later.

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -scheme whoisthere -derivedDataPath build build
open build/Build/Products/Debug/whoisthere.app
swift test   # core library tests
```

To regenerate the screenshots above (needs Google Chrome):

```sh
scripts/screenshots.sh
```

## Releasing

Needs a Developer ID Application certificate in your keychain. Store notarization credentials once:

```sh
xcrun notarytool store-credentials <profile> --apple-id <you@example.com> --team-id <TEAMID>
```

Then build, sign, notarize and staple:

```sh
DEVELOPMENT_TEAM=<TEAMID> NOTARY_PROFILE=<profile> scripts/release.sh
```

The result is `build/whoisthere-<version>.zip`. Verify with:

```sh
spctl -a -vv build/export/whoisthere.app   # accepted, source=Notarized Developer ID
```

## License

[MIT](LICENSE)
