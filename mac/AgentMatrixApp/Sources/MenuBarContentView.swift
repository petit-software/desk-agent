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
                Text("DeskAgent")
                    .font(.headline)
                Spacer()
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stateColor)
            }

            Divider()

            MatrixConnectionRow(
                connected: coordinator.isConnected,
                title: connectionTitle,
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

                Button {
                    Task { await coordinator.setPaused(!coordinator.isPaused) }
                } label: {
                    Label(
                        coordinator.isPaused ? "Resume Display" : "Pause Display",
                        systemImage: coordinator.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help(
                    coordinator.isPaused
                        ? "Resume matrix updates"
                        : "Turn off matrix lights while continuing to track Codex"
                )

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
                    settingsControl
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

    private var connectionTitle: String {
        guard coordinator.isConnected else { return "Matrix disconnected" }
        return coordinator.isUsingPhysicalDevice ? "Matrix connected" : "Simulator active"
    }

    @ViewBuilder
    private var settingsControl: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    private var lastEventLabel: String {
        guard let event = coordinator.lastEvent else { return "Waiting for the first lifecycle event" }
        return "Last event: \(event.event.rawValue)"
    }

    private var stateColor: Color {
        if coordinator.isPaused { return .secondary }
        return switch coordinator.displayState {
        case .needsInput: .orange
        case .finished: .green
        case .error: .red
        case .working: .cyan
        default: .secondary
        }
    }

    private var statusTitle: String {
        coordinator.isPaused ? "Paused" : coordinator.displayState.title
    }

    private var statusSymbol: String {
        coordinator.isPaused ? "pause.circle.fill" : coordinator.displayState.symbolName
    }
}

#Preview("Menu Bar Popover") {
    MenuBarContentView(
        coordinator: MatrixCoordinator(transport: SimulatorMatrixTransport()),
        openSimulator: {},
        openOnboarding: {}
    )
}
