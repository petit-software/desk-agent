import AgentMatrixCore
import AgentMatrixProtocol
import AgentMatrixSimulator
import SwiftUI

@main
struct AgentMatrixApp: App {
    @StateObject private var runtime: AppRuntime

    init() {
        let runtime = AppRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        runtime.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarSceneContent(runtime: runtime)
        } label: {
            MenuBarLabel(coordinator: runtime.coordinator)
        }
        .menuBarExtraStyle(.window)

        Window("Matrix Simulator", id: "simulator") {
            SimulatorView(coordinator: runtime.coordinator, transport: runtime.transport)
        }
        .defaultSize(width: 920, height: 660)

        Window("Agent Matrix Setup", id: "onboarding") {
            OnboardingSceneContent(runtime: runtime)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(runtime: runtime)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var coordinator: MatrixCoordinator

    var body: some View {
        Image(systemName: coordinator.displayState.symbolName)
            .accessibilityLabel("Agent Matrix, \(coordinator.displayState.title)")
    }
}

private struct MenuBarSceneContent: View {
    @ObservedObject var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContentView(
            coordinator: runtime.coordinator,
            openSimulator: { openWindow(id: "simulator") },
            openOnboarding: { openWindow(id: "onboarding") }
        )
    }
}

private struct OnboardingSceneContent: View {
    @ObservedObject var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        OnboardingView(
            openSimulator: { openWindow(id: "simulator") },
            installIntegration: runtime.installIntegration
        )
    }
}

#Preview("Menu Bar Label") {
    MenuBarLabel(coordinator: MatrixCoordinator(transport: SimulatorMatrixTransport()))
        .padding()
}

#Preview("Menu Bar Scene") {
    MenuBarSceneContent(runtime: AppRuntime())
}

#Preview("Onboarding Scene") {
    OnboardingSceneContent(runtime: AppRuntime())
}
