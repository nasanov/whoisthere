import AppKit
import ServiceManagement
import SwiftUI
import WhoIsThereCore

struct SettingsView: View {
    static let showAllKey = "showAllPorts"

    let store: ServerStore
    @AppStorage(SettingsView.showAllKey) private var showAll = false
    @State private var launchAtLogin = false
    @State private var needsApproval = false
    @State private var loginError: String?

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if needsApproval {
                    HStack(spacing: 6) {
                        Text("Approve in System Settings › Login Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
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
            readLoginStatus()
            NSApp.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readLoginStatus() // back from System Settings
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
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        readLoginStatus()
    }

    /// `.requiresApproval` means registered but blocked until the user allows it in
    /// System Settings; the toggle shows it as on so the hint makes sense.
    private func readLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
        if needsApproval { loginError = nil } // the approval hint explains it
    }
}
