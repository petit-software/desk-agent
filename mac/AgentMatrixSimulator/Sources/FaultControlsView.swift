import SwiftUI

public struct FaultControlsView: View {
    private let transport: SimulatorMatrixTransport
    @State private var deviceConnected = true
    @State private var delayedResponses = false
    @State private var wrongProtocol = false
    @State private var frozen = false

    public init(transport: SimulatorMatrixTransport) {
        self.transport = transport
    }

    public var body: some View {
        Form {
            Toggle("Device connected", isOn: $deviceConnected)
                .onChange(of: deviceConnected) { connected in
                    Task {
                        if connected {
                            await transport.reconnect()
                        } else {
                            await transport.disconnect()
                        }
                    }
                }
            Toggle("Delay responses", isOn: $delayedResponses)
                .onChange(of: delayedResponses) { enabled in
                    Task { await transport.setResponseDelay(enabled ? .milliseconds(900) : .zero) }
                }
            Toggle("Wrong protocol version", isOn: $wrongProtocol)
                .onChange(of: wrongProtocol) { enabled in
                    Task { await transport.setWrongProtocolVersion(enabled) }
                }
            Toggle("Freeze firmware", isOn: $frozen)
                .onChange(of: frozen) { enabled in
                    Task { await transport.firmware.setFrozen(enabled) }
                }
            HStack {
                Button("Drop Next ACK", systemImage: "arrow.down.to.line.compact") {
                    Task { await transport.dropNextACK() }
                }
                Button("Malformed Response", systemImage: "exclamationmark.triangle") {
                    Task { await transport.sendMalformedResponse() }
                }
            }
            HStack {
                Button("Expire Heartbeat", systemImage: "timer") {
                    Task { await transport.firmware.forceHeartbeatTimeout() }
                }
                Button("Reset Firmware", systemImage: "arrow.counterclockwise") {
                    Task { await transport.firmware.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Fault Controls") {
    FaultControlsView(transport: SimulatorMatrixTransport())
        .frame(width: 420)
        .padding()
}
