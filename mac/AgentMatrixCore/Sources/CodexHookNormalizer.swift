import AgentMatrixProtocol
import Foundation

public enum HookNormalizationError: LocalizedError, Sendable {
    case inputTooLarge
    case malformedJSON
    case missingEvent

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge: "Hook input exceeded 2 MB."
        case .malformedJSON: "Hook input was not a JSON object."
        case .missingEvent: "Hook input did not contain a supported lifecycle event."
        }
    }
}

public enum CodexHookNormalizer {
    public static let maximumInputBytes = 2 * 1_024 * 1_024
    public static let maximumWorkingDirectoryLength = 1_024

    public static func normalize(_ data: Data, now: Date = Date()) throws -> NormalizedAgentEvent {
        guard data.count <= maximumInputBytes else { throw HookNormalizationError.inputTooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookNormalizationError.malformedJSON
        }
        guard let rawEvent = string(in: object, keys: ["hook_event_name", "event", "eventName"]),
              let lifecycleEvent = lifecycleEvent(for: rawEvent) else {
            throw HookNormalizationError.missingEvent
        }

        let sessionID = string(in: object, keys: ["session_id", "sessionId"]) ?? "codex-unknown-session"
        let turnID = string(in: object, keys: ["turn_id", "turnId"])
        let cwd = string(in: object, keys: ["cwd", "working_directory"]).map {
            String($0.prefix(maximumWorkingDirectoryLength))
        }
        let toolName = string(in: object, keys: ["tool_name", "toolName"])

        return NormalizedAgentEvent(
            source: .codex,
            event: lifecycleEvent,
            sessionID: sessionID,
            turnID: turnID,
            workingDirectory: cwd,
            toolName: toolName,
            sentAtUnixMilliseconds: Int64(now.timeIntervalSince1970 * 1_000)
        )
    }

    public static func integrationError(now: Date = Date()) -> NormalizedAgentEvent {
        NormalizedAgentEvent(
            source: .codex,
            event: .integrationError,
            sessionID: "codex-integration",
            sentAtUnixMilliseconds: Int64(now.timeIntervalSince1970 * 1_000)
        )
    }

    public static func lifecycleEvent(for rawEvent: String) -> AgentLifecycleEvent? {
        switch rawEvent {
        case "SessionStart": .sessionStarted
        case "UserPromptSubmit": .turnStarted
        case "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop": .activity
        case "PermissionRequest": .approvalRequired
        case "Stop": .turnFinished
        case "SessionEnd": .sessionEnded
        default: nil
        }
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}
