import Foundation

public enum Format {
    public static func uptime(from: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(from)))
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        let d = s / 86400
        return d == 1 ? "1 day" : "\(d) days"
    }

    public static func abbreviatedPath(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        let h = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    public static func memory(_ bytes: UInt64) -> String {
        let gib = 1_073_741_824.0
        let b = Double(bytes)
        if b >= gib { return String(format: "%.1f GB", b / gib) }
        return "\(Int((b / 1_048_576).rounded())) MB"
    }

    public static func headerTitle(count: Int) -> String {
        switch count {
        case 0: return "No dev servers running"
        case 1: return "1 server running"
        default: return "\(count) servers running"
        }
    }
}
