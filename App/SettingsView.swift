import AppKit
import ServiceManagement
import SwiftUI
import WhoIsThereCore

struct SettingsView: View {
    static let showAllKey = "showAllPorts"

    let store: ServerStore
    @AppStorage(SettingsView.showAllKey) private var showAll = false
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Show all listening ports", isOn: $showAll)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            NSApp.activate()
        }
        .onChange(of: showAll) { _, value in store.showAll = value }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }
}
