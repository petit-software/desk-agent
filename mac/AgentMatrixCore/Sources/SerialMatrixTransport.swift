import AgentMatrixProtocol
import Darwin
import Foundation

public struct SerialConnectionInfo: Equatable, Sendable {
    public let path: String
    public let identity: DeviceIdentity

    public init(path: String, identity: DeviceIdentity) {
        self.path = path
        self.identity = identity
    }
}

public enum SerialPortDiscovery {
    public static func calloutDevices(in directory: URL = URL(fileURLWithPath: "/dev")) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.usbserial") }
            .sorted()
            .map { directory.appendingPathComponent($0).path }
    }
}

public actor SerialMatrixTransport: MatrixTransport {
    public nonisolated let events: AsyncStream<MatrixTransportEvent>

    private let continuation: AsyncStream<MatrixTransportEvent>.Continuation
    private let candidatePaths: @Sendable () -> [String]
    private let handshakeTimeout: TimeInterval
    private var descriptor: Int32 = -1
    private var readBuffer = Data()
    private var connection: SerialConnectionInfo?
    private var discoveryMessage = "No USB serial device has been checked."

    public init(
        candidatePaths: @escaping @Sendable () -> [String] = { SerialPortDiscovery.calloutDevices() },
        handshakeTimeout: TimeInterval = 0.5
    ) {
        self.candidatePaths = candidatePaths
        self.handshakeTimeout = handshakeTimeout
        let pair = AsyncStream.makeStream(of: MatrixTransportEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    public func connect() async {
        closeCurrentPort()
        continuation.yield(.searching)

        let paths = candidatePaths()
        guard !paths.isEmpty else {
            discoveryMessage = "No USB serial device found. Connect the matrix and retry."
            continuation.yield(.recoverableError(discoveryMessage))
            return
        }

        for path in paths {
            do {
                let candidate = try openConfiguredPort(at: path)
                descriptor = candidate
                readBuffer.removeAll(keepingCapacity: true)
                if let identity = try performHandshake() {
                    connection = SerialConnectionInfo(path: path, identity: identity)
                    discoveryMessage = "Connected to \(identity.hardwareID)."
                    continuation.yield(.connected(identity))
                    return
                }
            } catch {
                discoveryMessage = error.localizedDescription
            }
            closeCurrentPort()
        }

        discoveryMessage = "USB serial device found, but it did not answer AM1 HELLO. Flash DeskAgent firmware and retry."
        continuation.yield(.recoverableError(discoveryMessage))
    }

    public func disconnect() async {
        let wasConnected = connection != nil
        closeCurrentPort()
        if wasConnected {
            continuation.yield(.disconnected)
        }
    }

    public func send(_ command: MatrixCommand) async throws {
        guard descriptor >= 0, connection != nil else { throw SerialTransportError.disconnected }

        do {
            try writeLine(command.wireValue)
            let deadline = Date().addingTimeInterval(0.75)
            while Date() < deadline {
                guard let response = try readResponse(until: deadline) else { break }
                continuation.yield(.response(response))
                if response.sequence == command.sequence || command.sequence == nil {
                    return
                }
            }
            throw SerialTransportError.responseTimeout
        } catch {
            continuation.yield(.recoverableError(error.localizedDescription))
            if let serialError = error as? SerialTransportError {
                switch serialError {
                case .disconnected, .readFailed, .writeFailed:
                    closeCurrentPort()
                    continuation.yield(.disconnected)
                case .openFailed, .configurationFailed, .responseTimeout:
                    break
                }
            }
            throw error
        }
    }

    public func connectionInfo() -> SerialConnectionInfo? {
        connection
    }

    public func latestDiscoveryMessage() -> String {
        discoveryMessage
    }

    private func performHandshake() throws -> DeviceIdentity? {
        for _ in 0..<2 {
            tcflush(descriptor, TCIOFLUSH)
            readBuffer.removeAll(keepingCapacity: true)
            try writeLine(MatrixCommand.hello.wireValue)
            let deadline = Date().addingTimeInterval(handshakeTimeout)
            while Date() < deadline {
                guard let response = try readResponse(until: deadline) else { break }
                if case let .ready(version, hardwareID) = response {
                    continuation.yield(.response(response))
                    return DeviceIdentity(firmwareVersion: version, hardwareID: hardwareID)
                }
            }
        }
        return nil
    }

    private func openConfiguredPort(at path: String) throws -> Int32 {
        let port = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC) }
        guard port >= 0 else { throw SerialTransportError.openFailed(path, errno) }

        var settings = termios()
        guard tcgetattr(port, &settings) == 0 else {
            Darwin.close(port)
            throw SerialTransportError.configurationFailed(path)
        }
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard cfsetspeed(&settings, speed_t(B115200)) == 0,
              tcsetattr(port, TCSANOW, &settings) == 0 else {
            Darwin.close(port)
            throw SerialTransportError.configurationFailed(path)
        }
        return port
    }

    private func writeLine(_ line: String) throws {
        var data = Data((line + "\n").utf8)
        var offset = 0
        while offset < data.count {
            let remainingCount = data.count - offset
            let written = data.withUnsafeMutableBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), remainingCount)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                var writable = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                guard Darwin.poll(&writable, 1, 250) > 0 else { throw SerialTransportError.writeFailed }
            } else {
                throw SerialTransportError.writeFailed
            }
        }
    }

    private func readResponse(until deadline: Date) throws -> MatrixResponse? {
        while Date() < deadline {
            while let line = popLine() {
                if let response = MatrixResponse(line: line) { return response }
            }

            let remainingMilliseconds = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
            var readable = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let result = Darwin.poll(&readable, 1, remainingMilliseconds)
            if result == 0 { return nil }
            guard result > 0, readable.revents & Int16(POLLNVAL | POLLERR | POLLHUP) == 0 else {
                throw SerialTransportError.disconnected
            }

            var bytes = [UInt8](repeating: 0, count: 1_024)
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                readBuffer.append(contentsOf: bytes.prefix(count))
                if readBuffer.count > 8_192 {
                    readBuffer.removeFirst(readBuffer.count - 8_192)
                }
            } else if count == 0 {
                throw SerialTransportError.disconnected
            } else if errno != EAGAIN, errno != EWOULDBLOCK {
                throw SerialTransportError.readFailed
            }
        }
        return nil
    }

    private func popLine() -> String? {
        guard let newline = readBuffer.firstIndex(of: 0x0A) else { return nil }
        let line = String(decoding: readBuffer[..<newline], as: UTF8.self)
        readBuffer.removeSubrange(...newline)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func closeCurrentPort() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        descriptor = -1
        connection = nil
        readBuffer.removeAll(keepingCapacity: true)
    }
}

public enum SerialTransportError: LocalizedError, Sendable {
    case openFailed(String, Int32)
    case configurationFailed(String)
    case disconnected
    case responseTimeout
    case writeFailed
    case readFailed

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, code): "Could not open \(path) (error \(code))."
        case let .configurationFailed(path): "Could not configure \(path) for USB serial communication."
        case .disconnected: "The connected matrix is unavailable."
        case .responseTimeout: "The connected matrix did not acknowledge the command."
        case .writeFailed: "Could not write to the connected matrix."
        case .readFailed: "Could not read from the connected matrix."
        }
    }
}

private extension MatrixResponse {
    var sequence: UInt32? {
        switch self {
        case .ready, .status: nil
        case let .acknowledgement(sequence), let .error(sequence, _): sequence
        }
    }
}
