import AgentMatrixCore
import AgentMatrixProtocol
import Darwin
import Foundation
import XCTest

final class SerialMatrixTransportTests: XCTestCase {
    func testDiscoveryKeepsOnlyUSBCalloutDevices() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["cu.usbmodem1101", "cu.usbserial-1420", "tty.usbmodem1101", "cu.Bluetooth-Incoming-Port"] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }

        XCTAssertEqual(
            SerialPortDiscovery.calloutDevices(in: directory),
            ["cu.usbmodem1101", "cu.usbserial-1420"].map { directory.appendingPathComponent($0).path }
        )
    }

    func testSerialTransportHandshakesAndSendsSemanticStateOverPTY() async throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: Int(PATH_MAX))
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        guard master >= 0, slave >= 0 else { return XCTFail("Could not create pseudo-terminal") }
        defer {
            Darwin.close(master)
            Darwin.close(slave)
        }

        let path = String(cString: name)
        let responder = Task.detached { () -> Bool in
            var buffer = Data()
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                var readable = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
                guard Darwin.poll(&readable, 1, 250) >= 0 else { return false }
                guard readable.revents & Int16(POLLIN) != 0 else { continue }

                var bytes = [UInt8](repeating: 0, count: 512)
                let count = bytes.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(master, rawBuffer.baseAddress, rawBuffer.count)
                }
                guard count > 0 else { continue }
                buffer.append(contentsOf: bytes.prefix(count))

                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[..<newline], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer.removeSubrange(...newline)

                    if line == MatrixCommand.hello.wireValue {
                        Self.write("AM1 READY 1.2.3 test-matrix\n", to: master)
                    } else if case let .state(sequence, state, ttl) = MatrixCommand(line: line) {
                        guard state == .working, ttl == 8_000 else { return false }
                        Self.write("AM1 ACK \(sequence)\n", to: master)
                        return true
                    }
                }
            }
            return false
        }

        let transport = SerialMatrixTransport(candidatePaths: { [path] }, handshakeTimeout: 0.25)
        await transport.connect()
        let connection = await transport.connectionInfo()
        XCTAssertEqual(
            connection,
            SerialConnectionInfo(
                path: path,
                identity: DeviceIdentity(firmwareVersion: "1.2.3", hardwareID: "test-matrix")
            )
        )

        try await transport.send(.state(sequence: 7, state: .working, ttlMilliseconds: 8_000))
        let didAcknowledgeState = await responder.value
        XCTAssertTrue(didAcknowledgeState)
        await transport.disconnect()
    }

    private static func write(_ string: String, to descriptor: Int32) {
        let data = Data(string.utf8)
        let count = data.count
        data.withUnsafeBytes { buffer in
            _ = Darwin.write(descriptor, buffer.baseAddress, count)
        }
    }
}
