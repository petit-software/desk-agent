import AgentMatrixProtocol
import Darwin
import Foundation

public enum AgentMatrixSocket {
    public static var path: String { "/tmp/agent-matrix-\(getuid()).sock" }
    public static let maximumPacketBytes = 4_096
}

public enum UnixDatagramError: LocalizedError, Sendable {
    case pathTooLong
    case foreignSocketOwner
    case socketCreation(Int32)
    case bind(Int32)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong: "The local Agent Matrix socket path is too long."
        case .foreignSocketOwner: "The local Agent Matrix socket belongs to another user."
        case let .socketCreation(code): "Could not create local socket (errno \(code))."
        case let .bind(code): "Could not bind local socket (errno \(code))."
        }
    }
}

public enum UnixDatagramClient {
    public static func send(_ data: Data, to path: String = AgentMatrixSocket.path) {
        guard data.count <= AgentMatrixSocket.maximumPacketBytes,
              let address = socketAddress(path: path) else { return }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        data.withUnsafeBytes { bytes in
            withUnsafePointer(to: address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    _ = Darwin.sendto(
                        descriptor,
                        bytes.baseAddress,
                        bytes.count,
                        MSG_DONTWAIT,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
        }
    }
}

public final class AgentEventServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.bartbak.AgentMatrix.event-server")
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let path: String

    public init(path: String = AgentMatrixSocket.path) {
        self.path = path
    }

    deinit { stop() }

    public func start(handler: @escaping @Sendable (NormalizedAgentEvent) -> Void) throws {
        stop()
        try removeStaleSocket()
        guard let address = socketAddress(path: path) else { throw UnixDatagramError.pathTooLong }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw UnixDatagramError.socketCreation(errno) }
        let bindResult = withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw UnixDatagramError.bind(code)
        }
        chmod(path, S_IRUSR | S_IWUSR)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        self.descriptor = descriptor

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.receiveAvailablePackets(handler: handler)
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        if isCurrentUserOwner(path: path) { unlink(path) }
    }

    private func receiveAvailablePackets(handler: @escaping @Sendable (NormalizedAgentEvent) -> Void) {
        var buffer = [UInt8](repeating: 0, count: AgentMatrixSocket.maximumPacketBytes)
        while descriptor >= 0 {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            let data = Data(buffer.prefix(Int(count)))
            if let event = try? JSONDecoder().decode(NormalizedAgentEvent.self, from: data), event.v == 1 {
                handler(event)
            }
        }
    }

    private func removeStaleSocket() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard isCurrentUserOwner(path: path) else { throw UnixDatagramError.foreignSocketOwner }
        unlink(path)
    }
}

private func socketAddress(path: String) -> sockaddr_un? {
    let bytes = path.utf8CString
    var address = sockaddr_un()
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { destination in
        bytes.withUnsafeBytes { source in
            memcpy(destination, source.baseAddress, source.count)
        }
    }
    return address
}

private func isCurrentUserOwner(path: String) -> Bool {
    var metadata = stat()
    guard lstat(path, &metadata) == 0 else { return false }
    return metadata.st_uid == getuid()
}
