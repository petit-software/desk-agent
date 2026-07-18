import AgentMatrixProtocol
import XCTest

final class ProtocolTests: XCTestCase {
    func testCommandRoundTrip() {
        let command = MatrixCommand.state(sequence: 41, state: .needsInput, ttlMilliseconds: 8_000)
        XCTAssertEqual(command.wireValue, "AM1 STATE 41 NEEDS_INPUT 8000")
        XCTAssertEqual(MatrixCommand(line: command.wireValue), command)
    }

    func testResponseParsingRejectsWrongProtocol() {
        XCTAssertEqual(
            MatrixResponse(line: "AM1 READY 1.0.0 waveshare-rp2040-matrix"),
            .ready(firmwareVersion: "1.0.0", hardwareID: "waveshare-rp2040-matrix")
        )
        XCTAssertNil(MatrixResponse(line: "AM2 READY 1.0.0 matrix"))
        XCTAssertNil(MatrixResponse(line: "AM1 ACK overflow"))
    }

    func testEveryAnimationHasValidFrames() {
        for state in DisplayState.allCases {
            let animation = GeneratedAnimations.animation(for: state)
            XCTAssertFalse(animation.frames.isEmpty, state.rawValue)
            XCTAssertTrue(animation.frames.allSatisfy { $0.pixels.count == MatrixFrame.pixelCount })
            XCTAssertTrue(animation.frames.allSatisfy { $0.durationMilliseconds > 0 })
        }
    }

    func testWorkingAnimationUsesRotatingStarFrames() {
        let animation = GeneratedAnimations.animation(for: .working)
        XCTAssertEqual(animation.frames.count, 4)
        XCTAssertEqual(animation.frames.map(\.durationMilliseconds), [180, 180, 180, 180])

        for index in 1..<animation.frames.count {
            XCTAssertEqual(animation.frames[index].pixels, rotateClockwise(animation.frames[index - 1].pixels))
        }
    }

    func testBootingAnimationSweepsEveryRowInEveryVisibleColor() {
        let animation = GeneratedAnimations.animation(for: .booting)
        let colors = [
            RGBPixel(red: 255, green: 255, blue: 255),
            RGBPixel(red: 0, green: 120, blue: 255),
            RGBPixel(red: 0, green: 220, blue: 255),
            RGBPixel(red: 255, green: 120, blue: 0),
            RGBPixel(red: 0, green: 255, blue: 80),
            RGBPixel(red: 255, green: 0, blue: 0)
        ]

        XCTAssertEqual(animation.frames.count, colors.count * 5)
        for (index, frame) in animation.frames.enumerated() {
            let activeRow = index % 5
            let color = colors[index / 5]
            XCTAssertEqual(frame.durationMilliseconds, 120)
            for pixelIndex in frame.pixels.indices {
                XCTAssertEqual(frame.pixels[pixelIndex], pixelIndex / 5 == activeRow ? color : .off)
            }
        }
    }

    private func rotateClockwise(_ pixels: [RGBPixel]) -> [RGBPixel] {
        (0..<5).flatMap { row in
            (0..<5).map { column in
                pixels[(4 - column) * 5 + row]
            }
        }
    }
}
