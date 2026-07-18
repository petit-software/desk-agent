import AgentMatrixProtocol
import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    private enum Keys {
        static let brightness = "matrixBrightness"
        static let pauseDisplayWhileMacSleeps = "pauseDisplayWhileMacSleeps"
    }

    enum DisplayTarget: String, CaseIterable, Identifiable {
        case automatic
        case hardware
        case simulator

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Published var launchAtLogin = false
    @Published var finishedDuration = 10.0
    @Published var showSimulatorAutomatically = true
    @Published var diagnosticLogging = false
    @Published var displayTarget: DisplayTarget = .automatic
    @Published var mirrorHorizontally = false
    @Published var rotation = 0
    @Published var pauseDisplayWhileMacSleeps: Bool {
        didSet {
            guard persistsChanges else { return }
            defaults.set(pauseDisplayWhileMacSleeps, forKey: Keys.pauseDisplayWhileMacSleeps)
        }
    }
    @Published var brightness: UInt8 {
        didSet {
            let clamped = min(max(brightness, 1), GeneratedAnimations.brightnessLimit)
            if brightness != clamped {
                brightness = clamped
                return
            }
            guard persistsChanges else { return }
            defaults.set(Int(brightness), forKey: Keys.brightness)
        }
    }

    private let defaults: UserDefaults
    private let persistsChanges: Bool

    init(defaults: UserDefaults = .standard, persistsChanges: Bool = true) {
        self.defaults = defaults
        self.persistsChanges = persistsChanges
        pauseDisplayWhileMacSleeps = defaults.object(forKey: Keys.pauseDisplayWhileMacSleeps) == nil
            ? true
            : defaults.bool(forKey: Keys.pauseDisplayWhileMacSleeps)
        let savedBrightness = defaults.object(forKey: Keys.brightness) as? NSNumber
        brightness = UInt8(min(
            max(savedBrightness?.intValue ?? Int(GeneratedAnimations.defaultBrightness), 1),
            Int(GeneratedAnimations.brightnessLimit)
        ))
    }
}
