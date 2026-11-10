import AppKit
import SwiftUI
import WhoIsThereCore

struct ServerListView: View {
    let store: ServerStore
    @State private var expanded: Set<ProcessIdentity>

    init(store: ServerStore, initiallyExpanded: Set<ProcessIdentity> = []) {
        self.store = store
        _expanded = State(initialValue: initiallyExpanded)
    }

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
                                    isKilling: store.killing.contains(server.id),
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
            .buttonStyle(FooterButtonStyle())
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .padding(6)
        .frame(width: 420)
        .background(MenuWindowObserver { store.isMenuOpen = $0 })
        .modifier(CaptureOpenSettings())
        .onChange(of: store.servers) { _, servers in
            expanded.formIntersection(servers.map(\.id))
        }
    }

    private func toggle(_ id: ProcessIdentity) {
        withAnimation(.snappy(duration: 0.22)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
}

/// Plain text button with a rounded highlight on hover and a darker one while pressed.
private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovered)
        }
    }
}
