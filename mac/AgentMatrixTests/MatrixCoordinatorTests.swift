import AgentMatrixCore
import AgentMatrixProtocol
import Foundation
import XCTest

@MainActor
final class MatrixCoordinatorTests: XCTestCase {
    func testInitialBrightnessIsSentAfterConnecting() async {
        let transport = RecordingMatrixTransport()
        let coordinator = MatrixCoordinator(
            transport: transport,
            initialBrightness: 32
        )

        XCTAssertEqual(coordinator.brightness, 32)
        coordinator.start()
        let reachedCondition = await waitUntil {
            await transport.brightnessCommandCount(for: 32) >= 1
        }
        XCTAssertTrue(reachedCondition)
        coordinator.stop()
    }

    func testHeartbeatRenewsWorkingStateLease() async {
        let transport = RecordingMatrixTransport()
        let coordinator = MatrixCoordinator(
            transport: transport,
            heartbeatInterval: .milliseconds(40),
            stateTTLMilliseconds: 200
        )

        coordinator.start()
        var reachedCondition = await waitUntil { coordinator.isConnected }
        XCTAssertTrue(reachedCondition)

        await coordinator.setDisplayState(.working)
        reachedCondition = await waitUntil {
            await transport.stateCommandCount(for: .working) >= 2
        }
        XCTAssertTrue(reachedCondition)
        coordinator.stop()
    }

    func testFinishedStateExpiresThroughLeaseRefresh() async {
        let transport = RecordingMatrixTransport()
        let reducer = AgentStateReducer(finishedDuration: 0.12)
        let coordinator = MatrixCoordinator(
            transport: transport,
            reducer: reducer,
            heartbeatInterval: .milliseconds(40),
            stateTTLMilliseconds: 200
        )

        coordinator.start()
        var reachedCondition = await waitUntil { coordinator.isConnected }
        XCTAssertTrue(reachedCondition)

        let event = NormalizedAgentEvent(
            source: .codex,
            event: .turnFinished,
            sessionID: "session",
            turnID: "turn",
            sentAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            eventInstanceID: UUID()
        )
        await coordinator.receive(event)
        XCTAssertEqual(coordinator.displayState, .finished)

        reachedCondition = await waitUntil(timeout: .seconds(1)) {
            guard coordinator.displayState == .idle else { return false }
            return await transport.stateCommandCount(for: .idle) >= 1
        }
        XCTAssertTrue(reachedCondition)
        coordinator.stop()
    }

    func testPauseBlanksDisplayAndResumeShowsLatestState() async {
        let transport = RecordingMatrixTransport()
        let coordinator = MatrixCoordinator(
            transport: transport,
            heartbeatInterval: .milliseconds(40),
            stateTTLMilliseconds: 200
        )

        coordinator.start()
        var reachedCondition = await waitUntil { coordinator.isConnected }
        XCTAssertTrue(reachedCondition)

        let startedAt = Int64(Date().timeIntervalSince1970 * 1_000)
        await coordinator.receive(NormalizedAgentEvent(
            source: .codex,
            event: .turnStarted,
            sessionID: "session",
            turnID: "turn",
            sentAtUnixMilliseconds: startedAt,
            eventInstanceID: UUID()
        ))
        await coordinator.setPaused(true)
        XCTAssertTrue(coordinator.isPaused)

        reachedCondition = await waitUntil {
            await transport.brightnessCommandCount(for: 0) >= 2
        }
        XCTAssertTrue(reachedCondition)

        let needsInputBefore = await transport.stateCommandCount(for: .needsInput)
        await coordinator.receive(NormalizedAgentEvent(
            source: .codex,
            event: .approvalRequired,
            sessionID: "session",
            turnID: "turn",
            sentAtUnixMilliseconds: startedAt + 1,
            eventInstanceID: UUID()
        ))
        XCTAssertEqual(coordinator.displayState, .needsInput)
        let needsInputWhilePaused = await transport.stateCommandCount(for: .needsInput)
        XCTAssertEqual(needsInputWhilePaused, needsInputBefore)

        await coordinator.setPaused(false)
        XCTAssertFalse(coordinator.isPaused)
        reachedCondition = await waitUntil {
            await transport.stateCommandCount(for: .needsInput) >= 1
        }
        XCTAssertTrue(reachedCondition)
        let restoredBrightness = await transport.brightnessCommandCount(
            for: GeneratedAnimations.defaultBrightness
        )
        XCTAssertGreaterThanOrEqual(restoredBrightness, 1)
        coordinator.stop()
    }

    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor RecordingMatrixTransport: MatrixTransport {
    nonisolated let events: AsyncStream<MatrixTransportEvent>

    private let continuation: AsyncStream<MatrixTransportEvent>.Continuation
    private var commands: [MatrixCommand] = []

    init() {
        let pair = AsyncStream.makeStream(of: MatrixTransportEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    func connect() async {
        continuation.yield(.connected(DeviceIdentity(
            firmwareVersion: "test",
            hardwareID: "physical-test-matrix"
        )))
    }

    func disconnect() async {
        continuation.yield(.disconnected)
    }

    func send(_ command: MatrixCommand) async throws {
        commands.append(command)
        if let sequence = command.sequence {
            continuation.yield(.response(.acknowledgement(sequence: sequence)))
        }
    }

    func stateCommandCount(for state: DisplayState) -> Int {
        commands.reduce(into: 0) { count, command in
            if case let .state(_, commandState, _) = command, commandState == state {
                count += 1
            }
        }
    }

    func brightnessCommandCount(for value: UInt8) -> Int {
        commands.reduce(into: 0) { count, command in
            if case let .brightness(_, commandValue) = command, commandValue == value {
                count += 1
            }
        }
    }
}
