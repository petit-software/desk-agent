import AgentMatrixSimulator
import SwiftUI

struct DeveloperSettingsView: View {
    let transport: SimulatorMatrixTransport

    var body: some View {
        FaultControlsView(transport: transport)
    }
}

#Preview("Developer Settings") {
    DeveloperSettingsView(transport: SimulatorMatrixTransport())
        .frame(width: 520, height: 400)
}
