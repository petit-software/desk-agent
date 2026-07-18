import AgentMatrixCore
import Foundation
import XCTest

final class UF2FirmwareFlasherTests: XCTestCase {
    func testFindsMarkedRPIRP2Volume() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let volume = root.appendingPathComponent("RPI-RP2", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        try Data("UF2 Bootloader".utf8).write(to: volume.appendingPathComponent("INFO_UF2.TXT"))

        XCTAssertEqual(
            UF2FirmwareFlasher(volumesDirectory: root).bootloaderVolume()?.resolvingSymlinksInPath(),
            volume.resolvingSymlinksInPath()
        )
    }

    func testIgnoresUnmarkedVolumeWithMatchingName() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("RPI-RP2", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertNil(UF2FirmwareFlasher(volumesDirectory: root).bootloaderVolume())
    }

    func testRejectsMalformedFirmware() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firmware = root.appendingPathComponent("DeskAgent.uf2")
        try Data(repeating: 0, count: 512).write(to: firmware)

        XCTAssertThrowsError(try UF2FirmwareFlasher(volumesDirectory: root).validateFirmware(at: firmware)) { error in
            XCTAssertEqual(error as? UF2FirmwareError, .invalidFirmware)
        }
    }

    func testCopiesValidatedFirmwareToBootloaderVolume() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let volume = root.appendingPathComponent("RPI-RP2", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        try Data("UF2 Bootloader".utf8).write(to: volume.appendingPathComponent("INFO_UF2.TXT"))

        let firmware = root.appendingPathComponent("source.uf2")
        let firmwareData = makeUF2Block()
        try firmwareData.write(to: firmware)

        let destination = try UF2FirmwareFlasher(volumesDirectory: root).flash(
            firmwareURL: firmware,
            to: volume
        )

        XCTAssertEqual(destination.lastPathComponent, "DeskAgent.uf2")
        XCTAssertEqual(try Data(contentsOf: destination), firmwareData)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeUF2Block() -> Data {
        var data = Data(repeating: 0, count: 512)
        writeUInt32(0x0A32_4655, to: &data, at: 0)
        writeUInt32(0x9E5D_5157, to: &data, at: 4)
        writeUInt32(0x0AB1_6F30, to: &data, at: 508)
        return data
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
