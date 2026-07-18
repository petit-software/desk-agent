import AgentMatrixProtocol
import Foundation

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let source: AgentSource
    public var currentTurnID: String?
    public var workingDirectory: String?
    public var state: AgentSessionState
    public var lastEventAt: Date
    public var finishedAt: Date?
    public var lastEventInstanceID: UUID?

    public init(id: String, source: AgentSource, state: AgentSessionState, lastEventAt: Date) {
        self.id = id
        self.source = source
        self.state = state
        self.lastEventAt = lastEventAt
    }
}

public struct ReducerSnapshot: Sendable {
    public let sessions: [AgentSession]
    public let displayState: DisplayState
    public let lastEvent: NormalizedAgentEvent?

    public init(sessions: [AgentSession], displayState: DisplayState, lastEvent: NormalizedAgentEvent?) {
        self.sessions = sessions
        self.displayState = displayState
        self.lastEvent = lastEvent
    }
}

public actor AgentStateReducer {
    private var sessions: [String: AgentSession] = [:]
    private var seenEventIDs: Set<UUID> = []
    private var terminalEventTimes: [String: Int64] = [:]
    private var displayLevelError = false
    private var finishedDuration: TimeInterval

    public init(finishedDuration: TimeInterval = 10) {
        self.finishedDuration = finishedDuration
    }

    public func setFinishedDuration(_ duration: TimeInterval) {
        finishedDuration = max(0, duration)
    }

    @discardableResult
    public func receive(_ event: NormalizedAgentEvent, now: Date = Date()) -> ReducerSnapshot {
        guard event.v == 1, seenEventIDs.insert(event.eventInstanceID).inserted else {
            return snapshot(now: now, lastEvent: nil)
        }

        if event.event == .integrationError {
            displayLevelError = true
            return snapshot(now: now, lastEvent: event)
        }

        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID,
            source: event.source,
            state: .idle,
            lastEventAt: now
        )
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.sentAtUnixMilliseconds) / 1_000)
        let turnKey = "\(event.sessionID):\(event.turnID ?? session.currentTurnID ?? "unknown")"

        if (event.event == .activity || event.event == .approvalRequired),
           let terminalTime = terminalEventTimes[turnKey],
           event.sentAtUnixMilliseconds <= terminalTime {
            return snapshot(now: now, lastEvent: nil)
        }

        switch event.event {
        case .sessionStarted:
            if session.currentTurnID == nil { session.state = .idle }
        case .turnStarted:
            session.currentTurnID = event.turnID
            session.state = .working
            session.finishedAt = nil
            displayLevelError = false
        case .activity:
            session.state = .working
        case .approvalRequired:
            session.state = .needsInput
        case .turnFinished:
            session.state = .finished
            session.finishedAt = now
            terminalEventTimes[turnKey] = event.sentAtUnixMilliseconds
        case .turnFailed:
            session.state = .failed
            session.finishedAt = now
            terminalEventTimes[turnKey] = event.sentAtUnixMilliseconds
        case .sessionEnded:
            sessions.removeValue(forKey: event.sessionID)
            return snapshot(now: now, lastEvent: event)
        case .integrationError:
            break
        }

        session.currentTurnID = event.turnID ?? session.currentTurnID
        session.workingDirectory = event.workingDirectory ?? session.workingDirectory
        session.lastEventAt = eventDate
        session.lastEventInstanceID = event.eventInstanceID
        sessions[event.sessionID] = session
        return snapshot(now: now, lastEvent: event)
    }

    public func clearPresentationState() -> ReducerSnapshot {
        displayLevelError = false
        for key in sessions.keys where sessions[key]?.state == .failed || sessions[key]?.state == .finished {
            sessions[key]?.state = .idle
            sessions[key]?.finishedAt = nil
        }
        return snapshot(now: Date(), lastEvent: nil)
    }

    public func currentSnapshot(now: Date = Date()) -> ReducerSnapshot {
        snapshot(now: now, lastEvent: nil)
    }

    private func snapshot(now: Date, lastEvent: NormalizedAgentEvent?) -> ReducerSnapshot {
        for key in sessions.keys {
            if let finishedAt = sessions[key]?.finishedAt,
               now.timeIntervalSince(finishedAt) >= finishedDuration,
               sessions[key]?.state == .finished {
                sessions[key]?.state = .idle
                sessions[key]?.finishedAt = nil
            }
        }
        let displayState: DisplayState
        if displayLevelError || sessions.values.contains(where: { $0.state == .failed }) {
            displayState = .error
        } else if sessions.values.contains(where: { $0.state == .needsInput }) {
            displayState = .needsInput
        } else if sessions.values.contains(where: { $0.state == .working }) {
            displayState = .working
        } else if sessions.values.contains(where: { $0.state == .finished }) {
            displayState = .finished
        } else {
            displayState = .idle
        }
        return ReducerSnapshot(
            sessions: sessions.values.sorted { $0.lastEventAt > $1.lastEventAt },
            displayState: displayState,
            lastEvent: lastEvent
        )
    }
}
