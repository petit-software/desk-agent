import AgentMatrixProtocol
import SwiftUI

public struct StatePickerStrip: View {
    @Binding public var selection: DisplayState

    public init(selection: Binding<DisplayState>) {
        _selection = selection
    }

    public var body: some View {
        Picker("Matrix state", selection: $selection) {
            ForEach(DisplayState.allCases) { state in
                Label(state.title, systemImage: state.symbolName)
                    .tag(state)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Matrix state")
    }
}

public extension DisplayState {
    var symbolName: String {
        switch self {
        case .booting: "power"
        case .disconnected: "cable.connector.slash"
        case .idle: "circle.dotted"
        case .working: "bolt.fill"
        case .needsInput: "exclamationmark.bubble.fill"
        case .finished: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

#Preview("State Picker") {
    StatePickerStrip(selection: .constant(.working))
        .frame(width: 680)
        .padding()
}
