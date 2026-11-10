import AppKit
import SwiftUI
import WhoIsThereCore

struct ServerListView: View {
    let store: ServerStore
    @State private var expanded: Set<ProcessIdentity> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.servers.isEmpty {
                Text("No dev servers running")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                Text(Format.headerTitle(count: store.servers.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                ScrollView {
                    TimelineView(.everyMinute) { context in
                        VStack(spacing: 0) {
                            ForEach(store.servers) { server in
                                ServerRowView(
                                    server: server,
                                    now: context.date,
                                    isExpanded: expanded.contains(server.id),
                                    onToggleDetails: { toggle(server.id) },
                                    onKill: { Task { await store.kill(server) } }
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 480)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.vertical, 4)

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(6)
        .frame(width: 420)
        .background(MenuWindowObserver { store.isMenuOpen = $0 })
        .onChange(of: store.servers) { _, servers in
            expanded.formIntersection(servers.map(\.id))
        }
    }

    private func toggle(_ id: ProcessIdentity) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}
