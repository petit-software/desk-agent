import AgentMatrixCore
import AgentMatrixProtocol
import AgentMatrixSimulator
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var coordinator: MatrixCoordinator
    let openSimulator: () -> Void
    let openOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Agent Matrix")
                    .font(.headline)
                Spacer()
                Label(coordinator.displayState.title, systemImage: coordinator.displayState.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stateColor)
            }

            Divider()

            MatrixConnectionRow(
                connected: coordinator.isConnected,
                title: coordinator.isConnected ? "Simulator active" : "Matrix disconnected",
                detail: coordinator.connectionLabel
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Agent").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(coordinator.lastEvent?.source.rawValue.capitalized ?? "Codex")
                    Spacer()
                    Text(projectName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.callout)
                Text(lastEventLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            VStack(spacing: 8) {
                Button(action: openSimulator) {
                    Label("Open Matrix Simulator", systemImage: "square.grid.3x3.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button {
                        Task {
                            for state in [DisplayState.working, .needsInput, .finished, .idle] {
                                await coordinator.setDisplayState(state)
                                try? await Task.sleep(for: .milliseconds(650))
                            }
                        }
                    } label: {
                        Label("Test Display", systemImage: "play.fill")
                    }
                    Button(action: openOnboarding) {
                        Label("Setup", systemImage: "questionmark.circle")
                    }
                    Spacer()
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var projectName: String {
        guard let path = coordinator.lastEvent?.workingDirectory else { return "No active project" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var lastEventLabel: String {
        guard let event = coordinator.lastEvent else { return "Waiting for the first lifecycle event" }
        return "Last event: \(event.event.rawValue)"
    }

    private var stateColor: Color {
        switch coordinator.displayState {
        case .needsInput: .orange
        case .finished: .green
        case .error: .red
        case .working: .cyan
        default: .secondary
        }
    }
}

#Preview("Menu Bar Popover") {
    MenuBarContentView(
        coordinator: MatrixCoordinator(transport: SimulatorMatrixTransport()),
        openSimulator: {},
        openOnboarding: {}
    )
}
