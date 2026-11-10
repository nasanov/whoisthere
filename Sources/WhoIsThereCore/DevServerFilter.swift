import Foundation

public enum DevServerFilter {
    private static let denyList: Set<String> = ["postgres", "mysqld", "redis-server", "mongod", "claude"]
    private static let httpNames: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "php", "go", "java"]

    public static func includes(_ p: ProcessRecord, home: String, currentUID: UInt32, showAll: Bool) -> Bool {
        guard p.uid == currentUID else { return false }
        if showAll { return !p.listeningPorts.isEmpty }
        guard !visiblePorts(p).isEmpty else { return false }
        guard let cwd = p.cwd, cwd.hasPrefix(home + "/") else { return false }
        guard !denyList.contains(p.name) else { return false }
        if let path = p.executablePath, path.contains(".app/Contents/") { return false }
        return true
    }

    public static func visiblePorts(_ p: ProcessRecord) -> [UInt16] {
        var ports = Set(p.listeningPorts)
        var inspectFlagSeen = false
        for arg in p.arguments where arg.hasPrefix("--inspect") {
            inspectFlagSeen = true
            if let eq = arg.firstIndex(of: "=") {
                let value = arg[arg.index(after: eq)...]
                let portText = value.split(separator: ":").last.map(String.init) ?? ""
                if let port = UInt16(portText) { ports.remove(port) }
            }
        }
        if inspectFlagSeen {
            ports.remove(9229)
            ports.remove(9230)
        }
        return ports.sorted()
    }

    public static func looksHTTP(_ p: ProcessRecord, framework: Framework?) -> Bool {
        framework != nil || httpNames.contains(p.name)
    }
}
