import AgentMatrixCore
import AgentMatrixSimulator
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var coordinator: MatrixCoordinator

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                Toggle("Open simulator automatically", isOn: $preferences.showSimulatorAutomatically)
                Toggle("Diagnostic logging", isOn: $preferences.diagnosticLogging)
            }
            Section("Finished State") {
                LabeledContent("Duration") {
                    Stepper("\(Int(preferences.finishedDuration)) seconds", value: $preferences.finishedDuration, in: 2...60, step: 1)
                        .labelsHidden()
                    Text("\(Int(preferences.finishedDuration)) seconds")
                        .monospacedDigit()
                }
            }
            Section {
                Button("Clear Current State", systemImage: "xmark.circle") {
                    Task { await coordinator.clearPresentationState() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("General Settings") {
    GeneralSettingsView(
        preferences: AppPreferences(),
        coordinator: MatrixCoordinator(transport: SimulatorMatrixTransport())
    )
    .frame(width: 520, height: 380)
}
