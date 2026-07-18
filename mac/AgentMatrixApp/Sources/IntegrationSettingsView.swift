import AgentMatrixCore
import SwiftUI

struct IntegrationSettingsView: View {
    let status: CodexIntegrationStatus
    let message: String?
    let install: () -> Void
    let remove: () -> Void

    var body: some View {
        Form {
            Section("Codex") {
                LabeledContent("Status") {
                    Label(status.title, systemImage: status == .notInstalled ? "minus.circle" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status == .notInstalled ? Color.secondary : Color.orange)
                }
                LabeledContent("Configuration") {
                    Text("~/.codex/hooks.json")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section {
                HStack {
                    Button(status == .notInstalled ? "Install Hooks" : "Reinstall Hooks", systemImage: "terminal", action: install)
                    if status != .notInstalled {
                        Button("Remove Hooks", systemImage: "trash", role: .destructive, action: remove)
                    }
                }
            } footer: {
                Text(message ?? "After installation, open /hooks in Codex and review the DeskAgent command before trusting it.")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Integration Settings") {
    IntegrationSettingsView(status: .needsTrustReview, message: nil, install: {}, remove: {})
        .frame(width: 520, height: 360)
}
