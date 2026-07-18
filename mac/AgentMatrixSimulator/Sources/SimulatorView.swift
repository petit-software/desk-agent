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
    @State private var testTarget = SimulatorTestTarget.simulator
    @StateObject private var connectedDevice: ConnectedDeviceTester

    public init(
        coordinator: MatrixCoordinator,
        transport: SimulatorMatrixTransport,
        connectedDevice: ConnectedDeviceTester
    ) {
        self.coordinator = coordinator
        self.transport = transport
        _connectedDevice = StateObject(wrappedValue: connectedDevice)
        _selectedState = State(initialValue: coordinator.displayState)
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Matrix Simulator")
                            .font(.title2.weight(.semibold))
                        Text(targetStatusLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(renderedState.title, systemImage: renderedState.symbolName)
                        .foregroundStyle(renderedState == .error ? .red : .primary)
                }

                Picker("Test target", selection: $testTarget) {
                    ForEach(SimulatorTestTarget.allCases) { target in
                        Label(target.title, systemImage: target.symbolName)
                            .tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .onChange(of: testTarget) { target in
                    Task {
                        if target == .connectedDevice {
                            await connectPhysicalDevice()
                        } else {
                            connectedDevice.cancelFirmwareFlash()
                            await connectedDevice.disconnect()
                        }
                    }
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
                        Task {
                            await coordinator.setDisplayState(state)
                            if testTarget == .connectedDevice {
                                await connectedDevice.sendState(state)
                            }
                        }
                    }
            }
            .padding(24)

            VStack(alignment: .leading, spacing: 0) {
                Text(testTarget == .simulator ? "Virtual Device" : "Connected Device")
                    .font(.headline)
                    .padding(.bottom, 12)
                if testTarget == .simulator {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                        diagnosticRow("Connection", coordinator.connectionLabel)
                        diagnosticRow("Firmware", coordinator.firmwareVersion)
                        diagnosticRow("Brightness", brightnessLabel)
                        diagnosticRow("Heartbeat age", heartbeatLabel)
                        diagnosticRow("Last command", coordinator.lastCommand)
                        diagnosticRow("Last response", coordinator.lastResponse)
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                        diagnosticRow("Connection", connectedDevice.connectionLabel)
                        diagnosticRow("Port", connectedDevice.devicePath)
                        diagnosticRow("Firmware", connectedDevice.firmwareVersion)
                        diagnosticRow("Hardware", connectedDevice.hardwareID)
                        diagnosticRow("Brightness", brightnessLabel)
                        diagnosticRow("Last response", connectedDevice.lastResponse)
                    }
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
                if testTarget == .simulator {
                    Text("Fault Injection")
                        .font(.headline)
                    FaultControlsView(transport: transport)
                } else {
                    Text("Device Actions")
                        .font(.headline)
                        .padding(.bottom, 10)
                    HStack {
                        Button {
                            Task { await connectPhysicalDevice() }
                        } label: {
                            Label("Retry Connection", systemImage: "arrow.clockwise")
                        }
                        .disabled(connectedDevice.isConnecting)

                        Button {
                            Task { await connectedDevice.identify() }
                        } label: {
                            Label("Identify", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(!connectedDevice.isConnected)
                    }
                    .disabled(connectedDevice.firmwareFlashPhase.isActive)

                    HStack(spacing: 10) {
                        Button {
                            connectedDevice.startFirmwareFlash(
                                state: selectedState,
                                brightness: coordinator.brightness
                            )
                        } label: {
                            Label("Flash Firmware", systemImage: "arrow.down.to.line")
                        }
                        .disabled(connectedDevice.firmwareFlashPhase.isActive)

                        if connectedDevice.firmwareFlashPhase == .waitingForBootloader {
                            Button {
                                connectedDevice.cancelFirmwareFlash()
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                            }
                        }
                    }
                    .padding(.top, 10)

                    HStack(alignment: .top, spacing: 9) {
                        if connectedDevice.firmwareFlashPhase.isActive {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 2)
                        } else {
                            Image(systemName: firmwareFlashSymbol)
                                .foregroundStyle(firmwareFlashColor)
                                .frame(width: 16)
                        }
                        Text(connectedDevice.firmwareFlashMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)
                    if connectedDevice.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 10)
                            .accessibilityLabel("Connecting to matrix")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 340, idealWidth: 390)
        }
        .frame(minWidth: 840, minHeight: 600)
        .onAppear { selectedState = coordinator.displayState }
        .onDisappear {
            connectedDevice.cancelFirmwareFlash()
            Task { await connectedDevice.disconnect() }
        }
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

    private var targetStatusLabel: String {
        if testTarget == .connectedDevice {
            return connectedDevice.connectionLabel
        }
        return firmwareSnapshot?.connected == false ? "Virtual device unplugged" : coordinator.connectionLabel
    }

    private var brightnessLabel: String {
        "\(Int(coordinator.brightness) * 100 / Int(GeneratedAnimations.brightnessLimit))%"
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

    private func connectPhysicalDevice() async {
        await connectedDevice.connect(state: selectedState, brightness: coordinator.brightness)
    }

    private var firmwareFlashSymbol: String {
        switch connectedDevice.firmwareFlashPhase {
        case .ready: "externaldrive"
        case .waitingForBootloader, .flashing, .restarting: "arrow.down.to.line"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var firmwareFlashColor: Color {
        switch connectedDevice.firmwareFlashPhase {
        case .succeeded: .green
        case .failed: .red
        case .ready, .waitingForBootloader, .flashing, .restarting: .secondary
        }
    }
}

private enum SimulatorTestTarget: String, CaseIterable, Identifiable {
    case simulator
    case connectedDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simulator: "Simulator"
        case .connectedDevice: "Connected Device"
        }
    }

    var symbolName: String {
        switch self {
        case .simulator: "macwindow"
        case .connectedDevice: "cable.connector"
        }
    }
}

#Preview("Simulator") {
    let transport = SimulatorMatrixTransport()
    SimulatorView(
        coordinator: MatrixCoordinator(transport: transport),
        transport: transport,
        connectedDevice: ConnectedDeviceTester()
    )
}
