import Darwin
import Foundation

public enum CodexIntegrationStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case needsTrustReview
    case malformedConfiguration

    public var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .needsTrustReview: "Needs trust review"
        case .malformedConfiguration: "Configuration needs repair"
        }
    }
}

public enum CodexIntegrationError: LocalizedError, Sendable {
    case malformedConfiguration
    case bundledHelperMissing
    case helperInstallationFailed

    public var errorDescription: String? {
        switch self {
        case .malformedConfiguration: "The existing hooks.json is malformed and was not changed."
        case .bundledHelperMissing: "The bundled DeskAgent hook helper is missing."
        case .helperInstallationFailed: "The hook helper could not be installed."
        }
    }
}

public struct CodexIntegrationInstaller: Sendable {
    public static let eventNames = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "SubagentStart", "SubagentStop", "Stop"
    ]

    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var configurationURL: URL {
        homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    public var installedHelperURL: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/AgentMatrix/bin/agent-matrix-hook")
    }

    public func status() -> CodexIntegrationStatus {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return .notInstalled }
        guard let root = try? readRoot() else { return .malformedConfiguration }
        return containsOwnedHandler(in: root) ? .installed : .notInstalled
    }

    @discardableResult
    public func install(bundledHelperURL: URL) throws -> URL? {
        try installHelper(from: bundledHelperURL)
        let fileManager = FileManager.default
        let directory = configurationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"\(installedHelperURL.path)\" codex"

        for eventName in Self.eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            guard !groups.contains(where: { groupContains(command: command, group: $0) }) else { continue }
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": 2]]
            ]
            if ["PreToolUse", "PermissionRequest", "PostToolUse"].contains(eventName) {
                group["matcher"] = "*"
            }
            groups.append(group)
            hooks[eventName] = groups
        }
        root["hooks"] = hooks
        return try write(root: root)
    }

    @discardableResult
    public func uninstall() throws -> URL? {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return nil }
        var root = try readRoot()
        guard var hooks = root["hooks"] as? [String: Any] else { return nil }

        for (eventName, rawGroups) in hooks {
            guard let groups = rawGroups as? [[String: Any]] else { continue }
            hooks[eventName] = groups.map { group in
                var group = group
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                group["hooks"] = handlers.filter { handler in
                    guard let command = handler["command"] as? String else { return true }
                    return !isOwned(command: command)
                }
                return group
            }
        }
        root["hooks"] = hooks
        return try write(root: root)
    }

    private func readRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [:] }
        let data = try Data(contentsOf: configurationURL)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexIntegrationError.malformedConfiguration
        }
        return root
    }

    private func write(root: [String: Any]) throws -> URL? {
        let fileManager = FileManager.default
        let directory = configurationURL.deletingLastPathComponent()
        let backupURL: URL?
        if fileManager.fileExists(atPath: configurationURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let suffix = UUID().uuidString.prefix(8)
            let candidate = directory.appendingPathComponent(
                "hooks.json.agent-matrix-backup-\(formatter.string(from: Date()))-\(suffix)"
            )
            try fileManager.copyItem(at: configurationURL, to: candidate)
            backupURL = candidate
        } else {
            backupURL = nil
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let temporaryURL = directory.appendingPathComponent(".hooks.json.agent-matrix-\(UUID().uuidString)")
        try data.write(to: temporaryURL)
        chmod(temporaryURL.path, S_IRUSR | S_IWUSR)
        guard rename(temporaryURL.path, configurationURL.path) == 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw CocoaError(.fileWriteUnknown)
        }
        _ = try readRoot()
        return backupURL
    }

    private func installHelper(from bundledURL: URL) throws {
        guard FileManager.default.fileExists(atPath: bundledURL.path) else {
            throw CodexIntegrationError.bundledHelperMissing
        }
        let directory = installedHelperURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporaryURL = directory.appendingPathComponent(".agent-matrix-hook-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: bundledURL, to: temporaryURL)
        chmod(temporaryURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
        guard rename(temporaryURL.path, installedHelperURL.path) == 0 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CodexIntegrationError.helperInstallationFailed
        }
    }

    private func containsOwnedHandler(in root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { rawGroups in
            guard let groups = rawGroups as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { handler in
                    guard let command = handler["command"] as? String else { return false }
                    return isOwned(command: command)
                }
            }
        }
    }

    private func groupContains(command: String, group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { $0["command"] as? String == command }
    }

    private func isOwned(command: String) -> Bool {
        command.contains("/Library/Application Support/AgentMatrix/bin/agent-matrix-hook")
    }
}
