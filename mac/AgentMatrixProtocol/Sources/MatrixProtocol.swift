import Foundation

public enum MatrixCommand: Equatable, Sendable {
    case hello
    case state(sequence: UInt32, state: DisplayState, ttlMilliseconds: UInt32)
    case ping(sequence: UInt32)
    case brightness(sequence: UInt32, value: UInt8)
    case identify(sequence: UInt32)
    case resetState(sequence: UInt32)

    public var sequence: UInt32? {
        switch self {
        case .hello: nil
        case let .state(sequence, _, _), let .ping(sequence), let .brightness(sequence, _),
             let .identify(sequence), let .resetState(sequence): sequence
        }
    }

    public var wireValue: String {
        switch self {
        case .hello:
            "AM1 HELLO"
        case let .state(sequence, state, ttl):
            "AM1 STATE \(sequence) \(state.wireValue) \(ttl)"
        case let .ping(sequence):
            "AM1 PING \(sequence)"
        case let .brightness(sequence, value):
            "AM1 BRIGHTNESS \(sequence) \(value)"
        case let .identify(sequence):
            "AM1 IDENTIFY \(sequence)"
        case let .resetState(sequence):
            "AM1 RESET_STATE \(sequence)"
        }
    }

    public init?(line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        guard parts.count >= 2, parts[0] == "AM1" else { return nil }
        switch parts[1] {
        case "HELLO" where parts.count == 2:
            self = .hello
        case "STATE" where parts.count == 5:
            guard let sequence = UInt32(parts[2]), let state = DisplayState(wireValue: parts[3]),
                  let ttl = UInt32(parts[4]) else { return nil }
            self = .state(sequence: sequence, state: state, ttlMilliseconds: ttl)
        case "PING" where parts.count == 3:
            guard let sequence = UInt32(parts[2]) else { return nil }
            self = .ping(sequence: sequence)
        case "BRIGHTNESS" where parts.count == 4:
            guard let sequence = UInt32(parts[2]), let value = UInt8(parts[3]) else { return nil }
            self = .brightness(sequence: sequence, value: value)
        case "IDENTIFY" where parts.count == 3:
            guard let sequence = UInt32(parts[2]) else { return nil }
            self = .identify(sequence: sequence)
        case "RESET_STATE" where parts.count == 3:
            guard let sequence = UInt32(parts[2]) else { return nil }
            self = .resetState(sequence: sequence)
        default:
            return nil
        }
    }
}

public enum MatrixResponse: Equatable, Sendable {
    case ready(firmwareVersion: String, hardwareID: String)
    case acknowledgement(sequence: UInt32)
    case error(sequence: UInt32, code: String)
    case status(state: DisplayState, brightness: UInt8)

    public var wireValue: String {
        switch self {
        case let .ready(version, hardwareID): "AM1 READY \(version) \(hardwareID)"
        case let .acknowledgement(sequence): "AM1 ACK \(sequence)"
        case let .error(sequence, code): "AM1 ERR \(sequence) \(code)"
        case let .status(state, brightness): "AM1 STATUS \(state.wireValue) \(brightness)"
        }
    }

    public init?(line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        guard parts.count >= 3, parts[0] == "AM1" else { return nil }
        switch parts[1] {
        case "READY" where parts.count == 4:
            self = .ready(firmwareVersion: parts[2], hardwareID: parts[3])
        case "ACK" where parts.count == 3:
            guard let sequence = UInt32(parts[2]) else { return nil }
            self = .acknowledgement(sequence: sequence)
        case "ERR" where parts.count == 4:
            guard let sequence = UInt32(parts[2]) else { return nil }
            self = .error(sequence: sequence, code: parts[3])
        case "STATUS" where parts.count == 4:
            guard let state = DisplayState(wireValue: parts[2]), let brightness = UInt8(parts[3]) else { return nil }
            self = .status(state: state, brightness: brightness)
        default:
            return nil
        }
    }
}

public struct DeviceIdentity: Equatable, Sendable {
    public let firmwareVersion: String
    public let hardwareID: String

    public init(firmwareVersion: String, hardwareID: String) {
        self.firmwareVersion = firmwareVersion
        self.hardwareID = hardwareID
    }
}

public enum MatrixTransportEvent: Equatable, Sendable {
    case searching
    case connected(DeviceIdentity)
    case disconnected
    case response(MatrixResponse)
    case recoverableError(String)
    case fatalError(String)
}

public protocol MatrixTransport: Sendable {
    var events: AsyncStream<MatrixTransportEvent> { get }
    func connect() async
    func disconnect() async
    func send(_ command: MatrixCommand) async throws
}
