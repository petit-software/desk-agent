import SwiftUI

struct OnboardingView: View {
    private struct Step {
        let title: String
        let detail: String
        let symbol: String
    }

    let openSimulator: () -> Void
    let installIntegration: () -> Void
    @State private var stepIndex = 0

    private let steps = [
        Step(
            title: "Agent status at a glance",
            detail: "Agent Matrix reflects Codex lifecycle state on a simulated or physical 5x5 display.",
            symbol: "square.grid.3x3.square"
        ),
        Step(
            title: "Start with the simulator",
            detail: "Validate every state and the complete software path before connecting hardware.",
            symbol: "macwindow"
        ),
        Step(
            title: "Install the Codex integration",
            detail: "Agent Matrix adds scoped lifecycle handlers to ~/.codex/hooks.json and preserves unrelated hooks.",
            symbol: "terminal"
        ),
        Step(
            title: "Review the hooks",
            detail: "Run /hooks in Codex, inspect the Agent Matrix command, then trust it explicitly.",
            symbol: "checkmark.shield"
        ),
        Step(
            title: "Connect hardware later",
            detail: "Flash the provided UF2, attach the matrix over USB-C, and the app will identify it automatically.",
            symbol: "cable.connector"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            Image(systemName: steps[stepIndex].symbol)
                .font(.system(size: 46, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(steps[stepIndex].title)
                .font(.title2.weight(.semibold))
                .padding(.top, 18)
            Text(steps[stepIndex].detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .padding(.top, 8)
            Spacer(minLength: 28)
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == stepIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Divider().padding(.top, 22)
            HStack {
                Button("Back", systemImage: "chevron.left") {
                    stepIndex = max(0, stepIndex - 1)
                }
                .disabled(stepIndex == 0)
                Spacer()
                if stepIndex == 1 {
                    Button("Open Simulator", systemImage: "macwindow", action: openSimulator)
                }
                if stepIndex == 2 {
                    Button("Install Hooks", systemImage: "terminal", action: installIntegration)
                }
                Button(stepIndex == steps.count - 1 ? "Done" : "Continue", systemImage: "chevron.right") {
                    stepIndex = min(steps.count - 1, stepIndex + 1)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
        }
        .frame(width: 560, height: 390)
    }
}

#Preview("Onboarding") {
    OnboardingView(openSimulator: {}, installIntegration: {})
}
