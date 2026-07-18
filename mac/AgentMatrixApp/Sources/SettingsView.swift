import AgentMatrixCore
import AgentMatrixSimulator
import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: runtime.preferences, coordinator: runtime.coordinator)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettingsView(preferences: runtime.preferences, coordinator: runtime.coordinator)
                .tabItem { Label("Display", systemImage: "square.grid.3x3.square") }
            IntegrationSettingsView(
                status: runtime.integrationStatus,
                message: runtime.integrationMessage,
                install: runtime.installIntegration,
                remove: runtime.removeIntegration
            )
                .tabItem { Label("Integrations", systemImage: "terminal") }
            DeveloperSettingsView(transport: runtime.transport)
                .tabItem { Label("Developer", systemImage: "hammer") }
        }
        .frame(width: 560, height: 460)
    }
}

#Preview("Settings") {
    SettingsView(runtime: AppRuntime())
}
