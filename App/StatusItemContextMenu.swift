import AppKit
import SwiftUI
import os

/// Right-click (or control-click) on the menu bar icon shows a small menu with Settings
/// and Quit. MenuBarExtra has no API for this, so a local event monitor catches clicks
/// that land on the status bar window and pops the menu there instead of opening the panel.
@MainActor
final class StatusItemContextMenu: NSObject {
    static let shared = StatusItemContextMenu()

    /// Set from a SwiftUI view: on macOS 14+ the Settings scene can only be opened through
    /// the `openSettings` environment action.
    var openSettings: (() -> Void)?

    private var monitor: Any?
    private static let log = Logger(subsystem: "com.nasanov.whoisthere", category: "menu")

    func install() {
        guard monitor == nil else { return }
        Self.log.debug("context menu monitor installed")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            // Local monitors run on the main thread; NSEvent just isn't marked Sendable.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated {
                StatusItemContextMenu.shared.showMenuIfSecondaryClick(event)
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the click was on the menu bar icon and the menu was shown.
    private func showMenuIfSecondaryClick(_ event: NSEvent) -> Bool {
        let isSecondary = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isSecondary,
              let window = event.window,
              NSStringFromClass(type(of: window)).contains("StatusBarWindow"),
              let view = window.contentView
        else { return false }

        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
        return true
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func showSettings() {
        NSApp.activate()
        if let openSettings {
            openSettings()
            return
        }
        // Not captured yet (the panel hasn't been opened this launch): use the Settings item
        // SwiftUI puts in the app menu, then the legacy selector as a last resort.
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        if let menu = appMenu,
           let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            Self.log.debug("opening settings via app menu item")
            menu.performActionForItem(at: index)
        } else {
            Self.log.debug("opening settings via showSettingsWindow:")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// Hands the `openSettings` environment action to `StatusItemContextMenu`.
struct CaptureOpenSettings: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            StatusItemContextMenu.shared.openSettings = { openSettings() }
        }
    }
}
