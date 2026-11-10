import AppKit
import SwiftUI
import os

/// Reports whether the MenuBarExtra panel is showing. SwiftUI keeps the panel's content
/// alive between openings, so onAppear/onDisappear can't be trusted; instead this tracks
/// key status of the hosting NSWindow (the panel becomes key when opened and resigns
/// when dismissed).
struct MenuWindowObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private static let log = Logger(subsystem: "com.nasanov.whoisthere", category: "menu")

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Observers are dropped whenever the view leaves its window (window == nil).
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                   queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report(true) }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                   queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report(false) }
                },
            ]
            report(window.isKeyWindow)
        }

        private func report(_ open: Bool) {
            Self.log.debug("menu open: \(open, privacy: .public)")
            onChange?(open)
        }
    }
}
