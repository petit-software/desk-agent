import AgentMatrixProtocol
import AgentMatrixSimulator
import Foundation
import XCTest

final class RuntimeMatrixTransportTests: XCTestCase {
    func testAutomaticTargetMirrorsPreviewAndPrefersConnectedHardware() async throws {
        let simulator = SimulatorMatrixTransport()
        let hardware = ControlledMatrixTransport()
        let runtime = RuntimeMatrixTransport(
            simulator: simulator,
            hardware: hardware,
            retryInterval: .seconds(60)
        )

        await runtime.connect()
        var reachedDestination = await waitForDestination(.simulator, on: runtime)
        XCTAssertTrue(reachedDestination)

        try await runtime.send(.state(sequence: 1, state: .working, ttlMilliseconds: 8_000))
        var snapshot = await simulator.firmware.snapshot()
        XCTAssertEqual(snapshot.state, .working)
        var hardwareCommands = await hardware.commands()
        XCTAssertEqual(hardwareCommands, [])

        await hardware.announceConnection(
            DeviceIdentity(firmwareVersion: "9.9.9", hardwareID: "physical-test-matrix")
        )
        reachedDestination = await waitForDestination(.hardware, on: runtime)
        XCTAssertTrue(reachedDestination)

        let command = MatrixCommand.state(sequence: 2, state: .needsInput, ttlMilliseconds: 8_000)
        try await runtime.send(command)
        snapshot = await simulator.firmware.snapshot()
        XCTAssertEqual(snapshot.state, .needsInput)
        hardwareCommands = await hardware.commands()
        XCTAssertEqual(hardwareCommands, [command])

        await hardware.announceDisconnection()
        reachedDestination = await waitForDestination(.simulator, on: runtime)
        XCTAssertTrue(reachedDestination)
        await runtime.disconnect()
    }

    private func waitForDestination(
        _ destination: RuntimeMatrixDestination,
        on runtime: RuntimeMatrixTransport
    ) async -> Bool {
        for _ in 0..<100 {
            if await runtime.activeDestination() == destination { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private actor ControlledMatrixTransport: MatrixTransport {
    nonisolated let events: AsyncStream<MatrixTransportEvent>

    private let continuation: AsyncStream<MatrixTransportEvent>.Continuation
    private var sentCommands: [MatrixCommand] = []
    private var identity: DeviceIdentity?

    init() {
        let pair = AsyncStream.makeStream(of: MatrixTransportEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    func connect() async {
        continuation.yield(.searching)
        if let identity {
            continuation.yield(.connected(identity))
        } else {
            continuation.yield(.recoverableError("No test hardware"))
        }
    }

    func disconnect() async {
        identity = nil
        continuation.yield(.disconnected)
    }

    func send(_ command: MatrixCommand) async throws {
        guard identity != nil else { throw ControlledTransportError.disconnected }
        sentCommands.append(command)
        if let sequence = command.sequence {
            continuation.yield(.response(.acknowledgement(sequence: sequence)))
        }
    }

    func announceConnection(_ identity: DeviceIdentity) {
        self.identity = identity
        continuation.yield(.connected(identity))
    }

    func announceDisconnection() {
        identity = nil
        continuation.yield(.disconnected)
    }

    func commands() -> [MatrixCommand] {
        sentCommands
    }
}

private enum ControlledTransportError: Error {
    case disconnected
}
