import AgentMatrixProtocol
import SwiftUI

public struct MatrixGridView: View {
    public let frame: MatrixFrame
    public var brightness: UInt8
    public var rotation: Angle
    public var mirrored: Bool
    public var showsBloom: Bool

    public init(
        frame: MatrixFrame,
        brightness: UInt8 = GeneratedAnimations.brightnessLimit,
        rotation: Angle = .zero,
        mirrored: Bool = false,
        showsBloom: Bool = true
    ) {
        self.frame = frame
        self.brightness = brightness
        self.rotation = rotation
        self.mirrored = mirrored
        self.showsBloom = showsBloom
    }

    public var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let spacing = side * 0.035
            let pixelSide = (side - spacing * 6) / 5
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let intensity = Double(min(brightness, GeneratedAnimations.brightnessLimit)) / 64

            for row in 0..<5 {
                for column in 0..<5 {
                    let pixel = frame.pixels[row * 5 + column]
                    let rect = CGRect(
                        x: origin.x + spacing + CGFloat(column) * (pixelSide + spacing),
                        y: origin.y + spacing + CGFloat(row) * (pixelSide + spacing),
                        width: pixelSide,
                        height: pixelSide
                    )
                    let color = Color(
                        red: Double(pixel.red) / 255 * intensity,
                        green: Double(pixel.green) / 255 * intensity,
                        blue: Double(pixel.blue) / 255 * intensity
                    )
                    if showsBloom, pixel != .off {
                        context.drawLayer { layer in
                            layer.addFilter(.blur(radius: pixelSide * 0.22))
                            layer.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(color.opacity(0.5)))
                        }
                    }
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(pixel == .off ? Color(nsColor: .quaternaryLabelColor).opacity(0.18) : color)
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(12)
        .background(Color(red: 0.035, green: 0.037, blue: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .rotationEffect(rotation)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5 by 5 matrix")
    }
}

#Preview("Matrix Grid") {
    MatrixGridView(
        frame: GeneratedAnimations.animation(for: .working).frame(elapsedMilliseconds: 250)
    )
    .frame(width: 280, height: 280)
    .padding()
}
