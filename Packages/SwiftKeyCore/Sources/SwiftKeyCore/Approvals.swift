import Foundation

/// Code that runs only after the person approved its exact text.
public enum CodeKind: String, Codable, Sendable, CaseIterable {
    /// A `shell://` command.
    case shell
    /// A `dynamic://` command whose output is a menu.
    case dynamic
}

/// One piece of code that needs approval: its kind and its exact text.
public struct CodeRequest: Hashable, Sendable {
    public var kind: CodeKind
    /// The command exactly as the config gives it, after the `shell://` or `dynamic://` prefix.
    public var content: String

    public init(kind: CodeKind, content: String) {
        self.kind = kind
        self.content = content
    }

    /// The request of a config action string; nil for actions that run no code of their own
    /// (`launch://`, `open://`, `shortcut://`) and for anything else.
    public init?(action: String) {
        for kind in CodeKind.allCases where action.hasPrefix(kind.rawValue + "://") {
            self.init(kind: kind, content: String(action.dropFirst(kind.rawValue.count + 3)))
            return
        }
        return nil
    }

    /// Lower-case hex SHA-256 of the exact content. Any change, even a space, gives another hash.
    public var hash: String {
        MicroAppApprovals.hash(Data(content.utf8))
    }
}

extension Item.Action {
    /// True for actions that run code from the config: shell commands, dynamic menus and micro-apps.
    /// A deep link only navigates to these; running them needs a key press.
    public var runsCode: Bool {
        switch self {
        case .shell, .dynamic, .micro: return true
        case .group, .app, .url, .shortcut: return false
        }
    }
}

/// Everything the person approved, kept apart from the config so a copied config or a snippet
/// never approves anything.
/// JSON: {"version": 1, "commands": {"shell": [hash, …], "dynamic": [hash, …]},
/// "micro": {"id": hash}, "origins": {hash: "snippet “Name”"}}.
public struct Approvals: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version: Int = Approvals.currentVersion
    /// Kind → approved content hashes, sorted.
    public private(set) var commands: [String: [String]] = [:]
    /// Approved micro-apps: id → hash of the file with its libraries (see `MicroAppApprovals`).
    public var micro: MicroAppApprovals = MicroAppApprovals()
    /// Content hash → where the code came from, for code that did not come from the person's
    /// own editing, such as an imported snippet.
    public private(set) var origins: [String: String] = [:]

    public init() {}

    /// True only when exactly this content of this kind was approved.
    public func isApproved(_ request: CodeRequest) -> Bool {
        commands[request.kind.rawValue]?.contains(request.hash) == true
    }

    /// The requests that still need approval, each once, in their first order.
    public func pending(_ requests: [CodeRequest]) -> [CodeRequest] {
        var seen: Set<CodeRequest> = []
        return requests.filter { !isApproved($0) && seen.insert($0).inserted }
    }

    public mutating func approve(_ request: CodeRequest) {
        var hashes = Set(commands[request.kind.rawValue] ?? [])
        hashes.insert(request.hash)
        commands[request.kind.rawValue] = hashes.sorted()
    }

    /// Records where code came from, such as "snippet “Dev tools”". A later origin replaces it.
    public mutating func recordOrigin(_ origin: String, for request: CodeRequest) {
        origins[request.hash] = origin
    }

    public func origin(of request: CodeRequest) -> String? {
        origins[request.hash]
    }

    private enum CodingKeys: String, CodingKey { case version, commands, micro, origins }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        commands = try container.decodeIfPresent([String: [String]].self, forKey: .commands) ?? [:]
        let microApprovals = try container.decodeIfPresent([String: String].self, forKey: .micro) ?? [:]
        micro = MicroAppApprovals(approvals: microApprovals)
        origins = try container.decodeIfPresent([String: String].self, forKey: .origins) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(commands, forKey: .commands)
        try container.encode(micro.approvals, forKey: .micro)
        try container.encode(origins, forKey: .origins)
    }

    /// Sorted, pretty-printed JSON ending with "\n".
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(self)) ?? Data("{}".utf8)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// The stored approvals. Anything that is not a readable file of this format gives no
    /// approvals, so every command asks again: an unreadable file never approves anything.
    public static func decode(_ data: Data) -> Approvals {
        guard let decoded = try? JSONDecoder().decode(Approvals.self, from: data),
              decoded.version <= currentVersion else { return Approvals() }
        return decoded
    }
}
