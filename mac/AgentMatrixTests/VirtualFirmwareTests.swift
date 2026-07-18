import AgentMatrixProtocol
import AgentMatrixSimulator
import Foundation
import XCTest

final class VirtualFirmwareTests: XCTestCase {
    func testHandshakeStateAndHeartbeatTimeout() async {
        let firmware = VirtualFirmware()
        let base = Date(timeIntervalSince1970: 100)

        let hello = await firmware.receive(.hello, at: base)
        XCTAssertEqual(hello, .ready(firmwareVersion: "0.1.0", hardwareID: "virtual-rp2040-matrix"))

        let acknowledgement = await firmware.receive(
            .state(sequence: 1, state: .working, ttlMilliseconds: 8_000),
            at: base
        )
        XCTAssertEqual(acknowledgement, .acknowledgement(sequence: 1))
        var snapshot = await firmware.snapshot(at: base.addingTimeInterval(7.9))
        XCTAssertEqual(snapshot.state, .working)

        snapshot = await firmware.snapshot(at: base.addingTimeInterval(8.1))
        XCTAssertEqual(snapshot.state, .disconnected)
    }

    func testBrightnessIsClampedByFirmware() async {
        let firmware = VirtualFirmware()
        _ = await firmware.receive(.hello)
        _ = await firmware.receive(.brightness(sequence: 1, value: 255))
        let snapshot = await firmware.snapshot()
        XCTAssertEqual(snapshot.brightness, GeneratedAnimations.brightnessLimit)
    }
}
