import SwiftUI
import WhoIsThereCore

@main
struct WhoIsThereApp: App {
    @State private var store: ServerStore

    init() {
        #if DEBUG
        ScreenshotRenderer.runIfRequested()
        #endif
        let memoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "whoisthere/memory.json")
        let store = ServerStore(
            source: LiveProcessSource(),
            builder: ServerBuilder(home: NSHomeDirectory(), currentUID: getuid()),
            memory: ServerMemory(fileURL: memoryURL),
            killer: Killer(),
            currentUID: getuid()
        )
        store.showAll = UserDefaults.standard.bool(forKey: SettingsView.showAllKey)
        store.start()
        StatusItemContextMenu.shared.install()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            ServerListView(store: store)
        } label: {
            MenuBarLabel(count: store.servers.count)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
