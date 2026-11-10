#if DEBUG
import AppKit
import SwiftUI
import WhoIsThereCore

/// Debug-only. Launching with `WHOISTHERE_SCREENSHOTS=<dir>` renders the menu with sample
/// servers to PNGs (light and dark, collapsed and with details open) and quits.
@MainActor
enum ScreenshotRenderer {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["WHOISTHERE_SCREENSHOTS"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let servers = sampleServers(now: Date())
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(servers, expanded: [], appearance: appearance,
                   to: out.appending(path: "menu-\(name).png"))
            render(servers, expanded: [servers[1].id], appearance: appearance,
                   to: out.appending(path: "menu-details-\(name).png"))
        }
        exit(0)
    }

    private static func render(_ servers: [DevServer], expanded: Set<ProcessIdentity>,
                               appearance: NSAppearance.Name, to url: URL) {
        let store = ServerStore(
            source: LiveProcessSource(),
            builder: ServerBuilder(home: NSHomeDirectory(), currentUID: getuid()),
            memory: ServerMemory(fileURL: FileManager.default.temporaryDirectory
                .appending(path: "whoisthere-screenshots.json")),
            killer: Killer(),
            currentUID: getuid()
        )
        store.showSampleServers(servers)

        let view = NSHostingView(rootView: ServerListView(store: store, initiallyExpanded: expanded))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        settle()
        let size = view.fittingSize
        window.setContentSize(size)
        settle()

        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }

    private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    private static func sampleServers(now: Date) -> [DevServer] {
        let home = NSHomeDirectory()
        func server(_ pid: Int32, _ port: UInt16, _ project: String, _ branch: String?, _ folder: String,
                    _ framework: Framework?, _ starter: Starter?, minutesUp: Double, mb: UInt64,
                    _ command: String, otherPorts: [UInt16] = [], stale: StaleReason? = nil) -> DevServer {
            let start = now.addingTimeInterval(-minutesUp * 60)
            return DevServer(
                id: ProcessIdentity(pid: pid, startTime: start), pid: pid, primaryPort: port,
                otherPorts: otherPorts, projectName: project, branch: branch, folder: home + folder,
                framework: framework, starter: starter, startTime: start, residentBytes: mb << 20,
                command: command, isHTTP: true, stale: stale
            )
        }
        return [
            server(48102, 3000, "acme-web", "main", "/code/acme-web", .next, .terminal,
                   minutesUp: 128, mb: 412, "node node_modules/.bin/next dev"),
            server(48213, 3001, "acme-web", "feat/cart", "/code/acme-web-cart",
                   .next, .claude, minutesUp: 14, mb: 312, "node node_modules/.bin/next dev -p 3001"),
            server(51877, 4321, "docs", "main", "/code/docs", .astro, .editor("Cursor"),
                   minutesUp: 47, mb: 164, "node node_modules/.bin/astro dev"),
            server(40311, 5173, "dashboard", "fix/login", "/code/dashboard-login",
                   .vite, .terminal, minutesUp: 3 * 24 * 60 + 40, mb: 138, "node node_modules/.bin/vite",
                   stale: .worktreeDeleted),
            server(52004, 8000, "billing-api", "main", "/code/billing-api", .fastAPI, .claude,
                   minutesUp: 6, mb: 96, "python -m uvicorn app.main:app --reload"),
            server(39550, 8080, "storefront", "release/2.4", "/code/storefront", .remix, nil,
                   minutesUp: 2 * 24 * 60 + 300, mb: 201, "node node_modules/.bin/remix dev",
                   stale: .sessionClosed),
        ]
    }
}
#endif
