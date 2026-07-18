import AgentMatrixCore
import AgentMatrixProtocol
import AgentMatrixSimulator
import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var coordinator: MatrixCoordinator

    var body: some View {
        Form {
            Section("Target") {
                Picker("Display target", selection: $preferences.displayTarget) {
                    ForEach(AppPreferences.DisplayTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Matrix") {
                LabeledContent("Brightness") {
                    Slider(
                        value: Binding(
                            get: { Double(coordinator.brightness) },
                            set: { value in Task { await coordinator.updateBrightness(UInt8(value)) } }
                        ),
                        in: 1...64,
                        step: 1
                    )
                    .frame(width: 220)
                    Text("\(coordinator.brightness)")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }
                Picker("Rotation", selection: $preferences.rotation) {
                    Text("0°").tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                Toggle("Mirror horizontally", isOn: $preferences.mirrorHorizontally)
            }
            Section("State Tests") {
                HStack {
                    ForEach(DisplayState.allCases) { state in
                        Button {
                            Task { await coordinator.setDisplayState(state) }
                        } label: {
                            Image(systemName: state.symbolName)
                        }
                        .help(state.title)
                        .accessibilityLabel(state.title)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Display Settings") {
    DisplaySettingsView(
        preferences: AppPreferences(),
        coordinator: MatrixCoordinator(transport: SimulatorMatrixTransport())
    )
    .frame(width: 520, height: 420)
}
