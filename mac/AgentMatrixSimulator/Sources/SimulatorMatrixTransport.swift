import AgentMatrixProtocol
import Foundation

public actor SimulatorMatrixTransport: MatrixTransport {
    public nonisolated let events: AsyncStream<MatrixTransportEvent>

    public let firmware: VirtualFirmware
    private let continuation: AsyncStream<MatrixTransportEvent>.Continuation
    private var connected = false
    private var dropNextAcknowledgement = false
    private var responseDelay: Duration = .zero
    private var wrongProtocolVersion = false
    private var malformedResponse = false

    public init(firmware: VirtualFirmware = VirtualFirmware()) {
        self.firmware = firmware
        let pair = AsyncStream.makeStream(of: MatrixTransportEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    public func connect() async {
        continuation.yield(.searching)
        guard let response = await firmware.receive(.hello) else {
            continuation.yield(.disconnected)
            return
        }
        connected = true
        if wrongProtocolVersion {
            continuation.yield(.fatalError("Virtual device reported incompatible protocol AM2"))
            return
        }
        if case let .ready(version, hardwareID) = response {
            continuation.yield(.connected(DeviceIdentity(firmwareVersion: version, hardwareID: hardwareID)))
            continuation.yield(.response(response))
        }
    }

    public func disconnect() async {
        connected = false
        await firmware.setConnected(false)
        continuation.yield(.disconnected)
    }

    public func reconnect() async {
        await firmware.setConnected(true)
        await connect()
    }

    public func send(_ command: MatrixCommand) async throws {
        guard connected else { throw SimulatorTransportError.disconnected }
        if responseDelay > .zero { try? await Task.sleep(for: responseDelay) }
        guard let response = await firmware.receive(command) else {
            continuation.yield(.recoverableError("Virtual firmware did not respond"))
            return
        }
        if malformedResponse {
            malformedResponse = false
            continuation.yield(.recoverableError("Malformed virtual response"))
            return
        }
        if dropNextAcknowledgement, case .acknowledgement = response {
            dropNextAcknowledgement = false
            return
        }
        continuation.yield(.response(response))
    }

    public func dropNextACK() { dropNextAcknowledgement = true }
    public func setResponseDelay(_ delay: Duration) { responseDelay = delay }
    public func setWrongProtocolVersion(_ enabled: Bool) { wrongProtocolVersion = enabled }
    public func sendMalformedResponse() { malformedResponse = true }
}

public enum SimulatorTransportError: LocalizedError, Sendable {
    case disconnected

    public var errorDescription: String? { "The virtual matrix is disconnected." }
}
