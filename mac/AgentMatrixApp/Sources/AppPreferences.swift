import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
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
    @Published var displayTarget: DisplayTarget = .simulator
    @Published var mirrorHorizontally = false
    @Published var rotation = 0
}
