import SwiftUI
import WhoIsThereCore

@main
struct WhoIsThereApp: App {
    var body: some Scene {
        MenuBarExtra("whoisthere", systemImage: "network") {
            Text("whoisthere")
        }
        .menuBarExtraStyle(.window)
    }
}
