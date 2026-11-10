import Foundation

public enum WhoIsThereVersion {
    public static let current = "0.1.0"
}

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startTime: Date
    public init(pid: Int32, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }
}

public struct ProcessRecord: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var executablePath: String?
    public var arguments: [String]
    public var cwd: String?
    public var startTime: Date
    public var residentBytes: UInt64
    public var listeningPorts: [UInt16]

    public init(pid: Int32, ppid: Int32, uid: UInt32, name: String, executablePath: String?,
                arguments: [String], cwd: String?, startTime: Date, residentBytes: UInt64,
                listeningPorts: [UInt16]) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.cwd = cwd
        self.startTime = startTime
        self.residentBytes = residentBytes
        self.listeningPorts = listeningPorts
    }

    public var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }
}

public struct GitInfo: Equatable, Codable, Sendable {
    public var repoName: String
    public var branch: String
    public var isWorktree: Bool
    public init(repoName: String, branch: String, isWorktree: Bool) {
        self.repoName = repoName
        self.branch = branch
        self.isWorktree = isWorktree
    }
}

public enum Framework: String, Codable, Sendable {
    case next = "Next", vite = "Vite", astro = "Astro", remix = "Remix", nuxt = "Nuxt"
    case svelteKit = "SvelteKit", angular = "Angular", webpack = "Webpack"
    case django = "Django", flask = "Flask", fastAPI = "FastAPI", rails = "Rails"
    case phoenix = "Phoenix", bun = "Bun", deno = "Deno"
}

public enum Starter: Codable, Equatable, Sendable { case claude, terminal, editor(String) }

public enum StaleReason: Equatable, Sendable { case folderDeleted, worktreeDeleted, sessionClosed }

public struct DevServer: Identifiable, Equatable, Sendable {
    public var id: ProcessIdentity
    public var pid: Int32
    public var primaryPort: UInt16
    public var otherPorts: [UInt16]
    public var projectName: String
    public var branch: String?
    public var folder: String
    public var framework: Framework?
    public var starter: Starter?
    public var startTime: Date
    public var residentBytes: UInt64
    public var command: String
    public var isHTTP: Bool
    public var stale: StaleReason?

    public init(id: ProcessIdentity, pid: Int32, primaryPort: UInt16, otherPorts: [UInt16],
                projectName: String, branch: String?, folder: String, framework: Framework?,
                starter: Starter?, startTime: Date, residentBytes: UInt64, command: String,
                isHTTP: Bool, stale: StaleReason?) {
        self.id = id
        self.pid = pid
        self.primaryPort = primaryPort
        self.otherPorts = otherPorts
        self.projectName = projectName
        self.branch = branch
        self.folder = folder
        self.framework = framework
        self.starter = starter
        self.startTime = startTime
        self.residentBytes = residentBytes
        self.command = command
        self.isHTTP = isHTTP
        self.stale = stale
    }

    public var url: URL? { isHTTP ? URL(string: "http://localhost:\(primaryPort)") : nil }
}
