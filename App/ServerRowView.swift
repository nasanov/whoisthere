import AppKit
import SwiftUI
import WhoIsThereCore

struct ServerRowView: View {
    let server: DevServer
    let now: Date
    let isExpanded: Bool
    let isKilling: Bool
    let onToggleDetails: () -> Void
    let onKill: () -> Void

    @State private var isHovered = false

    private static let home = NSHomeDirectory()

    var body: some View {
        VStack(spacing: 0) {
            row
            // The details slide down inside their own clipped container, so they're revealed
            // from the row's bottom edge instead of showing through the translucent row.
            VStack(spacing: 0) {
                if isExpanded {
                    details
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        }
    }

    // MARK: Row

    private var row: some View {
        HStack(spacing: 10) {
            Text(String(server.primaryPort))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 44, alignment: .leading)
                .opacity(server.stale == nil ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let framework = server.framework {
                        Tag(text: framework.rawValue, warm: false)
                    }
                    if server.starter == .claude {
                        Tag(text: "Claude", warm: true)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Fade only the info: the actions stay fully opaque so they don't read as disabled.
            .opacity(server.stale == nil ? 1 : 0.55)

            HStack(spacing: 2) {
                if let url = server.url {
                    IconButton(symbol: "arrow.up.right.square", help: "Open in browser") {
                        NSWorkspace.shared.open(url)
                    }
                    IconButton(symbol: "doc.on.doc", help: "Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                IconButton(symbol: "chevron.down", rotation: isExpanded ? 180 : 0, help: "Details",
                           action: onToggleDetails)
                if isKilling {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                        .help("Stopping…")
                } else {
                    IconButton(symbol: "xmark.circle", help: "Kill", tint: .red, action: onKill)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered || isExpanded ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var title: String {
        if let branch = server.branch { return "\(server.projectName) · \(branch)" }
        return server.projectName
    }

    private var subtitle: String {
        var parts: [String] = []
        switch server.stale {
        case .worktreeDeleted: parts.append("worktree deleted")
        case .folderDeleted: parts.append("folder deleted")
        case .sessionClosed: parts.append("session closed")
        case nil: parts.append(Format.abbreviatedPath(server.folder, home: Self.home))
        }
        parts.append("up " + Format.uptime(from: server.startTime, now: now))
        switch server.starter {
        case .terminal: parts.append("you")
        case .editor(let name): parts.append(name)
        case .claude, nil: break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            DetailLine(label: "Folder") { Text(server.folder) }
            DetailLine(label: "Framework") { Text(server.framework?.rawValue ?? "Unknown") }
            DetailLine(label: "Started by") {
                Text("\(starterName) · \(Format.uptime(from: server.startTime, now: now)) ago")
            }
            DetailLine(label: "Memory") {
                Text("\(Format.memory(server.residentBytes)) · PID \(String(server.pid))")
            }
            DetailLine(label: "Command") {
                Text(server.command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            if !server.otherPorts.isEmpty {
                DetailLine(label: "Other ports") {
                    Text(server.otherPorts.map(String.init).joined(separator: ", "))
                }
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var starterName: String {
        switch server.starter {
        case .claude: "Claude Code"
        case .terminal: "You (terminal)"
        case .editor(let name): name
        case nil: "Unknown"
        }
    }
}

private struct Tag: View {
    let text: String
    let warm: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(warm ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(warm ? Color.orange.opacity(0.18) : Color.primary.opacity(0.08))
            )
            .fixedSize()
    }
}

private struct IconButton: View {
    let symbol: String
    var rotation: Double = 0
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .rotationEffect(.degrees(rotation))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle(tint: tint))
        .help(help)
    }
}

/// Borderless icon button with a rounded highlight on hover and a darker one while pressed.
private struct IconButtonStyle: ButtonStyle {
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, tint: tint)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let tint: Color?
        @State private var isHovered = false

        var body: some View {
            let highlight = tint ?? .primary
            configuration.label
                .foregroundStyle(tint ?? .primary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(highlight.opacity(configuration.isPressed ? 0.22 : isHovered ? 0.12 : 0))
                )
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovered)
        }
    }
}

private struct DetailLine<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
