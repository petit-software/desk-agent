import Foundation

public struct NormalizedAgentEvent: Codable, Equatable, Sendable {
    public let v: Int
    public let source: AgentSource
    public let event: AgentLifecycleEvent
    public let sessionID: String
    public let turnID: String?
    public let workingDirectory: String?
    public let toolName: String?
    public let sentAtUnixMilliseconds: Int64
    public let eventInstanceID: UUID

    public init(
        v: Int = 1,
        source: AgentSource,
        event: AgentLifecycleEvent,
        sessionID: String,
        turnID: String? = nil,
        workingDirectory: String? = nil,
        toolName: String? = nil,
        sentAtUnixMilliseconds: Int64,
        eventInstanceID: UUID = UUID()
    ) {
        self.v = v
        self.source = source
        self.event = event
        self.sessionID = sessionID
        self.turnID = turnID
        self.workingDirectory = workingDirectory
        self.toolName = toolName
        self.sentAtUnixMilliseconds = sentAtUnixMilliseconds
        self.eventInstanceID = eventInstanceID
    }

    enum CodingKeys: String, CodingKey {
        case v, source, event, toolName
        case sessionID = "sessionId"
        case turnID = "turnId"
        case workingDirectory = "cwd"
        case sentAtUnixMilliseconds = "sentAtUnixMs"
        case eventInstanceID = "eventInstanceId"
    }
}
