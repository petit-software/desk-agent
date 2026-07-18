import AgentMatrixCore
import AgentMatrixProtocol
import SwiftUI

public struct SimulatorView: View {
    @ObservedObject private var coordinator: MatrixCoordinator
    private let transport: SimulatorMatrixTransport
    @State private var selectedState: DisplayState
    @State private var rotation = Angle.zero
    @State private var mirrored = false
    @State private var firmwareSnapshot: VirtualFirmwareSnapshot?
    @State private var renderedFrame = GeneratedAnimations.animation(for: .booting).frame(elapsedMilliseconds: 0)

    public init(coordinator: MatrixCoordinator, transport: SimulatorMatrixTransport) {
        self.coordinator = coordinator
        self.transport = transport
        _selectedState = State(initialValue: coordinator.displayState)
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Matrix Simulator")
                            .font(.title2.weight(.semibold))
                        Text(firmwareSnapshot?.connected == false ? "Virtual device unplugged" : coordinator.connectionLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(renderedState.title, systemImage: renderedState.symbolName)
                        .foregroundStyle(renderedState == .error ? .red : .primary)
                }

                MatrixGridView(
                    frame: renderedFrame,
                    brightness: firmwareSnapshot?.brightness ?? coordinator.brightness,
                    rotation: rotation,
                    mirrored: mirrored
                )
                .frame(minWidth: 300, idealWidth: 440, maxWidth: 520, minHeight: 300, idealHeight: 440, maxHeight: 520)

                StatePickerStrip(selection: $selectedState)
                    .onChange(of: selectedState) { state in
                        Task { await coordinator.setDisplayState(state) }
                    }
            }
            .padding(24)

            VStack(alignment: .leading, spacing: 0) {
                Text("Device")
                    .font(.headline)
                    .padding(.bottom, 12)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    diagnosticRow("Connection", coordinator.connectionLabel)
                    diagnosticRow("Firmware", coordinator.firmwareVersion)
                    diagnosticRow(
                        "Brightness",
                        "\(Int(coordinator.brightness) * 100 / Int(GeneratedAnimations.brightnessLimit))%"
                    )
                    diagnosticRow("Heartbeat age", heartbeatLabel)
                    diagnosticRow("Last command", coordinator.lastCommand)
                    diagnosticRow("Last response", coordinator.lastResponse)
                }
                Divider().padding(.vertical, 18)
                Text("Orientation")
                    .font(.headline)
                    .padding(.bottom, 10)
                Picker("Rotation", selection: $rotation) {
                    Text("0°").tag(Angle.zero)
                    Text("90°").tag(Angle.degrees(90))
                    Text("180°").tag(Angle.degrees(180))
                    Text("270°").tag(Angle.degrees(270))
                }
                Toggle("Mirror horizontally", isOn: $mirrored)
                    .padding(.top, 8)
                Divider().padding(.vertical, 18)
                Text("Fault Injection")
                    .font(.headline)
                FaultControlsView(transport: transport)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 340, idealWidth: 390)
        }
        .frame(minWidth: 840, minHeight: 600)
        .onAppear { selectedState = coordinator.displayState }
        .task {
            while !Task.isCancelled {
                firmwareSnapshot = await transport.firmware.snapshot()
                renderedFrame = await transport.firmware.frame()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private var renderedState: DisplayState {
        firmwareSnapshot?.state ?? coordinator.displayState
    }

    private var heartbeatLabel: String {
        guard let age = firmwareSnapshot?.heartbeatAge else { return "No heartbeat" }
        return String(format: "%.1f seconds", max(0, age))
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

#Preview("Simulator") {
    let transport = SimulatorMatrixTransport()
    SimulatorView(coordinator: MatrixCoordinator(transport: transport), transport: transport)
}
