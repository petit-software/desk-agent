import Foundation

public struct UF2FirmwareFlasher: Sendable {
    public static let bootloaderVolumeName = "RPI-RP2"

    private static let blockSize = 512
    private static let firstMagic: UInt32 = 0x0A32_4655
    private static let secondMagic: UInt32 = 0x9E5D_5157
    private static let endMagic: UInt32 = 0x0AB1_6F30

    public let volumesDirectory: URL

    public init(volumesDirectory: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true)) {
        self.volumesDirectory = volumesDirectory
    }

    public func bootloaderVolume() -> URL? {
        let fileManager = FileManager.default
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: volumesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return candidates.first { candidate in
            guard candidate.lastPathComponent.caseInsensitiveCompare(Self.bootloaderVolumeName) == .orderedSame,
                  (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            return fileManager.fileExists(atPath: candidate.appendingPathComponent("INFO_UF2.TXT").path)
        }
    }

    public func validateFirmware(at firmwareURL: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: firmwareURL, options: .mappedIfSafe)
        } catch {
            throw UF2FirmwareError.unreadableFirmware
        }

        guard !data.isEmpty, data.count.isMultiple(of: Self.blockSize) else {
            throw UF2FirmwareError.invalidFirmware
        }

        for offset in stride(from: 0, to: data.count, by: Self.blockSize) {
            guard readUInt32(in: data, at: offset) == Self.firstMagic,
                  readUInt32(in: data, at: offset + 4) == Self.secondMagic,
                  readUInt32(in: data, at: offset + Self.blockSize - 4) == Self.endMagic else {
                throw UF2FirmwareError.invalidFirmware
            }
        }
    }

    @discardableResult
    public func flash(firmwareURL: URL, to volumeURL: URL) throws -> URL {
        try validateFirmware(at: firmwareURL)

        let markerURL = volumeURL.appendingPathComponent("INFO_UF2.TXT")
        guard volumeURL.lastPathComponent.caseInsensitiveCompare(Self.bootloaderVolumeName) == .orderedSame,
              FileManager.default.fileExists(atPath: markerURL.path) else {
            throw UF2FirmwareError.bootloaderUnavailable
        }

        let destinationURL = volumeURL.appendingPathComponent("DeskAgent.uf2")
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: firmwareURL, to: destinationURL)
        } catch {
            throw UF2FirmwareError.copyFailed(error.localizedDescription)
        }
        return destinationURL
    }

    private func readUInt32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

public enum UF2FirmwareError: LocalizedError, Equatable, Sendable {
    case unreadableFirmware
    case invalidFirmware
    case bootloaderUnavailable
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFirmware:
            "The bundled DeskAgent firmware could not be read."
        case .invalidFirmware:
            "The bundled firmware is not a valid UF2 image."
        case .bootloaderUnavailable:
            "The Pico BOOTSEL volume is no longer available."
        case let .copyFailed(message):
            "Firmware copy failed: \(message)"
        }
    }
}
