import SwiftUI

struct MatrixConnectionRow: View {
    let connected: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: connected ? "circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(connected ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Connection Row") {
    MatrixConnectionRow(connected: true, title: "Simulator", detail: "Virtual firmware 0.1.0")
        .frame(width: 320)
        .padding()
}
