import AgentMatrixProtocol
import Foundation

public struct VirtualFirmwareSnapshot: Equatable, Sendable {
    public let state: DisplayState
    public let brightness: UInt8
    public let lastSequence: UInt32
    public let connected: Bool
    public let heartbeatAge: TimeInterval?

    public init(state: DisplayState, brightness: UInt8, lastSequence: UInt32, connected: Bool, heartbeatAge: TimeInterval?) {
        self.state = state
        self.brightness = brightness
        self.lastSequence = lastSequence
        self.connected = connected
        self.heartbeatAge = heartbeatAge
    }
}

public actor VirtualFirmware {
    public static let firmwareVersion = "0.1.0"
    public static let hardwareID = "virtual-rp2040-matrix"

    private var state: DisplayState = .booting
    private var brightness: UInt8 = GeneratedAnimations.defaultBrightness
    private var lastHeartbeatAt: Date?
    private var heartbeatTTL: TimeInterval = 8
    private var lastSequence: UInt32 = 0
    private var connected = true
    private var bootedAt = Date()
    private var automaticBootTransitionPending = true
    private var frozen = false

    public init() {}

    public func receive(_ command: MatrixCommand, at now: Date = Date()) -> MatrixResponse? {
        guard connected, !frozen else { return nil }
        switch command {
        case .hello:
            if state == .booting {
                state = .disconnected
                automaticBootTransitionPending = false
            }
            return .ready(firmwareVersion: Self.firmwareVersion, hardwareID: Self.hardwareID)
        case let .state(sequence, newState, ttlMilliseconds):
            guard sequence != 0 else { return .error(sequence: 0, code: "INVALID_SEQUENCE") }
            if sequence != lastSequence {
                state = newState
                lastSequence = sequence
                automaticBootTransitionPending = false
                if newState == .booting {
                    bootedAt = now
                }
            }
            heartbeatTTL = TimeInterval(ttlMilliseconds) / 1_000
            lastHeartbeatAt = now
            return .acknowledgement(sequence: sequence)
        case let .ping(sequence):
            lastSequence = sequence
            lastHeartbeatAt = now
            return .acknowledgement(sequence: sequence)
        case let .brightness(sequence, value):
            lastSequence = sequence
            brightness = min(value, GeneratedAnimations.brightnessLimit)
            return .acknowledgement(sequence: sequence)
        case let .identify(sequence):
            lastSequence = sequence
            state = .booting
            bootedAt = now
            automaticBootTransitionPending = true
            return .acknowledgement(sequence: sequence)
        case let .resetState(sequence):
            lastSequence = sequence
            state = .idle
            lastHeartbeatAt = now
            automaticBootTransitionPending = false
            return .acknowledgement(sequence: sequence)
        }
    }

    public func tick(at now: Date = Date()) {
        guard connected, !frozen else { return }
        if state == .booting, automaticBootTransitionPending, now.timeIntervalSince(bootedAt) >= 1 {
            state = lastHeartbeatAt == nil ? .disconnected : .idle
            automaticBootTransitionPending = false
        }
        if let lastHeartbeatAt, now.timeIntervalSince(lastHeartbeatAt) >= heartbeatTTL {
            state = .disconnected
        }
    }

    public func frame(at now: Date = Date()) -> MatrixFrame {
        tick(at: now)
        let elapsed = max(0, Int(now.timeIntervalSince(bootedAt) * 1_000))
        return GeneratedAnimations.animation(for: state).frame(elapsedMilliseconds: elapsed)
    }

    public func snapshot(at now: Date = Date()) -> VirtualFirmwareSnapshot {
        tick(at: now)
        return VirtualFirmwareSnapshot(
            state: state,
            brightness: brightness,
            lastSequence: lastSequence,
            connected: connected,
            heartbeatAge: lastHeartbeatAt.map { now.timeIntervalSince($0) }
        )
    }

    public func setConnected(_ isConnected: Bool) {
        connected = isConnected
        if isConnected {
            state = .booting
            bootedAt = Date()
            automaticBootTransitionPending = true
        }
    }

    public func setFrozen(_ isFrozen: Bool) {
        frozen = isFrozen
    }

    public func forceHeartbeatTimeout() {
        lastHeartbeatAt = Date(timeIntervalSinceNow: -(heartbeatTTL + 1))
        tick()
    }

    public func reset() {
        state = .booting
        brightness = GeneratedAnimations.defaultBrightness
        lastHeartbeatAt = nil
        lastSequence = 0
        connected = true
        frozen = false
        bootedAt = Date()
        automaticBootTransitionPending = true
    }
}
