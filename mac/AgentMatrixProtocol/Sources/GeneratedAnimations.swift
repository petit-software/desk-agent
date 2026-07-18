import Foundation

public struct MatrixAnimation: Sendable {
    public let frames: [MatrixFrame]
    public let loops: Bool

    public init(frames: [MatrixFrame], loops: Bool) {
        self.frames = frames
        self.loops = loops
    }

    public func frame(elapsedMilliseconds: Int) -> MatrixFrame {
        guard frames.count > 1 else { return frames[0] }
        let total = frames.reduce(0) { $0 + $1.durationMilliseconds }
        let position = loops ? elapsedMilliseconds % total : min(elapsedMilliseconds, total - 1)
        var accumulated = 0
        for frame in frames {
            accumulated += frame.durationMilliseconds
            if position < accumulated { return frame }
        }
        return frames[frames.count - 1]
    }
}

public enum GeneratedAnimations {
    public static let brightnessLimit: UInt8 = 64
    public static let defaultBrightness: UInt8 = 16

    public static func animation(for state: DisplayState) -> MatrixAnimation {
        animations[state] ?? animations[.disconnected]!
    }

    private static let palette: [Character: RGBPixel] = [
        "0": .off,
        "d": RGBPixel(red: 24, green: 24, blue: 24),
        "W": RGBPixel(red: 255, green: 255, blue: 255),
        "B": RGBPixel(red: 0, green: 120, blue: 255),
        "C": RGBPixel(red: 0, green: 220, blue: 255),
        "A": RGBPixel(red: 255, green: 120, blue: 0),
        "G": RGBPixel(red: 0, green: 255, blue: 80),
        "R": RGBPixel(red: 255, green: 0, blue: 0)
    ]

    private static let animations: [DisplayState: MatrixAnimation] = [
        .booting: cumulativeRowFill(color: "W", duration: 150),
        .disconnected: animation(rows: [
            ["00000", "00000", "00d00", "00000", "00000"]
        ], duration: 1_000),
        .idle: animation(rows: [
            ["00000", "00000", "00C00", "00000", "00000"],
            ["00000", "00C00", "0C0C0", "00C00", "00000"],
            ["00000", "00000", "00C00", "00000", "00000"]
        ], duration: 600),
        .working: cumulativeColumnFill(color: "B", duration: 180),
        .needsInput: animation(rows: [
            ["00A00", "00A00", "00A00", "00000", "00A00"],
            ["00A00", "00A00", "00A00", "00000", "00000"]
        ], duration: 360),
        .finished: animation(rows: [
            ["00000", "0000G", "G00G0", "0GG00", "00000"]
        ], duration: 900, loops: false),
        .error: animation(rows: [
            ["R000R", "0R0R0", "00R00", "0R0R0", "R000R"],
            ["R000R", "00000", "00R00", "00000", "R000R"]
        ], duration: 250)
    ]

    private static func animation(rows: [[[Character]]], duration: Int, loops: Bool = true) -> MatrixAnimation {
        MatrixAnimation(
            frames: rows.map { frameRows in
                MatrixFrame(pixels: frameRows.flatMap { $0 }.map { palette[$0] ?? .off }, durationMilliseconds: duration)
            },
            loops: loops
        )
    }

    private static func animation(rows: [[String]], duration: Int, loops: Bool = true) -> MatrixAnimation {
        animation(rows: rows.map { $0.map(Array.init) }, duration: duration, loops: loops)
    }

    private static func cumulativeRowFill(color: Character, duration: Int) -> MatrixAnimation {
        let fillingFrames = (1...5).map { visibleRows in
            MatrixFrame(
                pixels: (0..<MatrixFrame.pixelCount).map { index in
                    index / 5 < visibleRows ? palette[color] ?? .off : .off
                },
                durationMilliseconds: duration
            )
        }
        let clearingFrames = (1...5).map { removedRows in
            MatrixFrame(
                pixels: (0..<MatrixFrame.pixelCount).map { index in
                    index / 5 >= removedRows ? palette[color] ?? .off : .off
                },
                durationMilliseconds: duration
            )
        }

        return MatrixAnimation(
            frames: fillingFrames + clearingFrames,
            loops: true
        )
    }

    private static func cumulativeColumnFill(color: Character, duration: Int) -> MatrixAnimation {
        let fillingFrames = (1...5).map { visibleColumns in
            MatrixFrame(
                pixels: (0..<MatrixFrame.pixelCount).map { index in
                    index % 5 < visibleColumns ? palette[color] ?? .off : .off
                },
                durationMilliseconds: duration
            )
        }
        let clearingFrames = (1...5).map { removedColumns in
            MatrixFrame(
                pixels: (0..<MatrixFrame.pixelCount).map { index in
                    index % 5 >= removedColumns ? palette[color] ?? .off : .off
                },
                durationMilliseconds: duration
            )
        }

        return MatrixAnimation(
            frames: fillingFrames + clearingFrames,
            loops: true
        )
    }
}
