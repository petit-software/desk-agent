import Darwin
import Foundation

private let maximumInputBytes = 2 * 1_024 * 1_024
private let maximumPacketBytes = 4_096
private let socketPath = "/tmp/agent-matrix-\(getuid()).sock"

private let input = FileHandle.standardInput.readDataToEndOfFile()
private var rawEventName: String?
private var outputEvent = "integrationError"
private var sessionID = "codex-integration"
private var turnID: String?
private var workingDirectory: String?
private var toolName: String?

if input.count <= maximumInputBytes,
   let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
    rawEventName = string(in: object, keys: ["hook_event_name", "event", "eventName"])
    sessionID = string(in: object, keys: ["session_id", "sessionId"]) ?? "codex-unknown-session"
    turnID = string(in: object, keys: ["turn_id", "turnId"])
    workingDirectory = string(in: object, keys: ["cwd", "working_directory"]).map { String($0.prefix(1_024)) }
    toolName = string(in: object, keys: ["tool_name", "toolName"])
    if let rawEventName, let normalized = normalizedEvent(rawEventName) {
        outputEvent = normalized
    }
}

var normalized: [String: Any] = [
    "v": 1,
    "source": "codex",
    "event": outputEvent,
    "sessionId": sessionID,
    "sentAtUnixMs": Int64(Date().timeIntervalSince1970 * 1_000),
    "eventInstanceId": UUID().uuidString
]
if let turnID { normalized["turnId"] = turnID }
if let workingDirectory { normalized["cwd"] = workingDirectory }
if let toolName { normalized["toolName"] = toolName }

if let packet = try? JSONSerialization.data(withJSONObject: normalized), packet.count <= maximumPacketBytes {
    send(packet: packet, path: socketPath)
}

if rawEventName == "Stop" {
    FileHandle.standardOutput.write(Data("{}\n".utf8))
}

exit(EXIT_SUCCESS)

private func normalizedEvent(_ event: String) -> String? {
    switch event {
    case "SessionStart": "sessionStarted"
    case "UserPromptSubmit": "turnStarted"
    case "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop": "activity"
    case "PermissionRequest": "approvalRequired"
    case "Stop": "turnFinished"
    case "SessionEnd": "sessionEnded"
    default: nil
    }
}

private func string(in object: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = object[key] as? String, !value.isEmpty { return value }
    }
    return nil
}

private func send(packet: Data, path: String) {
    let pathBytes = path.utf8CString
    var address = sockaddr_un()
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return }
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { destination in
        pathBytes.withUnsafeBytes { source in
            memcpy(destination, source.baseAddress, source.count)
        }
    }

    let descriptor = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
    guard descriptor >= 0 else { return }
    defer { Darwin.close(descriptor) }
    packet.withUnsafeBytes { bytes in
        withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                _ = Darwin.sendto(
                    descriptor,
                    bytes.baseAddress,
                    bytes.count,
                    MSG_DONTWAIT,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
    }
}
