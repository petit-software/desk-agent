import Foundation

public enum AgentSource: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case generic
}

public enum AgentLifecycleEvent: String, Codable, CaseIterable, Sendable {
    case sessionStarted
    case turnStarted
    case activity
    case approvalRequired
    case turnFinished
    case turnFailed
    case sessionEnded
    case integrationError
}

public enum AgentSessionState: String, Codable, Sendable {
    case idle
    case working
    case needsInput
    case finished
    case failed
}

public enum DisplayState: String, Codable, CaseIterable, Identifiable, Sendable {
    case booting
    case disconnected
    case idle
    case working
    case needsInput
    case finished
    case error

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .booting: "Booting"
        case .disconnected: "Disconnected"
        case .idle: "Idle"
        case .working: "Working"
        case .needsInput: "Needs Input"
        case .finished: "Finished"
        case .error: "Error"
        }
    }

    public var wireValue: String {
        switch self {
        case .needsInput: "NEEDS_INPUT"
        default: rawValue.uppercased()
        }
    }

    public init?(wireValue: String) {
        if wireValue == "NEEDS_INPUT" {
            self = .needsInput
        } else {
            self.init(rawValue: wireValue.lowercased())
        }
    }
}

public struct RGBPixel: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let off = RGBPixel(red: 0, green: 0, blue: 0)
}

public struct MatrixFrame: Codable, Equatable, Sendable {
    public static let pixelCount = 25
    public let pixels: [RGBPixel]
    public let durationMilliseconds: Int

    public init(pixels: [RGBPixel], durationMilliseconds: Int) {
        precondition(pixels.count == Self.pixelCount)
        self.pixels = pixels
        self.durationMilliseconds = durationMilliseconds
    }
}
