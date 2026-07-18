import AgentMatrixProtocol
import Combine
import Foundation

@MainActor
public final class MatrixCoordinator: ObservableObject {
    @Published public private(set) var displayState: DisplayState = .booting
    @Published public private(set) var connectionLabel = "Starting matrix connection"
    @Published public private(set) var isConnected = false
    @Published public private(set) var lastCommand = "AM1 HELLO"
    @Published public private(set) var lastResponse = "Waiting for matrix"
    @Published public private(set) var firmwareVersion = "-"
    @Published public private(set) var hardwareID = "-"
    @Published public private(set) var lastEvent: NormalizedAgentEvent?
    @Published public private(set) var isPaused = false
    @Published public var brightness: UInt8 = GeneratedAnimations.defaultBrightness

    public let reducer: AgentStateReducer
    private let transport: any MatrixTransport
    private let heartbeatInterval: Duration
    private let stateTTLMilliseconds: UInt32
    private var sequence: UInt32 = 0
    private var eventTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var followsReducer = true
    private var isManuallyPaused = false
    private var isPausedForSystemSleep = false

    public init(
        transport: any MatrixTransport,
        reducer: AgentStateReducer = AgentStateReducer(),
        initialBrightness: UInt8 = GeneratedAnimations.defaultBrightness,
        heartbeatInterval: Duration = .seconds(2),
        stateTTLMilliseconds: UInt32 = 8_000
    ) {
        self.transport = transport
        self.reducer = reducer
        brightness = min(max(initialBrightness, 1), GeneratedAnimations.brightnessLimit)
        self.heartbeatInterval = heartbeatInterval
        self.stateTTLMilliseconds = stateTTLMilliseconds
    }

    public var isUsingPhysicalDevice: Bool {
        isConnected && hardwareID != "-" && !hardwareID.hasPrefix("virtual-")
    }

    deinit {
        eventTask?.cancel()
        heartbeatTask?.cancel()
    }

    public func start() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, events = transport.events] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.handleTransportEvent(event)
            }
        }
        Task { await transport.connect() }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let heartbeatInterval = self?.heartbeatInterval else { return }
                try? await Task.sleep(for: heartbeatInterval)
                guard let self, self.isConnected else { continue }
                await self.refreshStateLease()
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        heartbeatTask?.cancel()
        eventTask = nil
        heartbeatTask = nil
        Task { await transport.disconnect() }
    }

    public func receive(_ event: NormalizedAgentEvent) async {
        let snapshot = await reducer.receive(event)
        lastEvent = event
        await setReducedDisplayState(snapshot.displayState)
    }

    public func setDisplayState(_ state: DisplayState) async {
        followsReducer = false
        await applyDisplayState(state)
    }

    public func endDisplayStateTest() async {
        let snapshot = await reducer.currentSnapshot()
        await setReducedDisplayState(snapshot.displayState)
    }

    private func setReducedDisplayState(_ state: DisplayState) async {
        followsReducer = true
        await applyDisplayState(state)
    }

    private func applyDisplayState(_ state: DisplayState) async {
        displayState = state
        guard isConnected, !isPaused else { return }
        let command = MatrixCommand.state(
            sequence: nextSequence(),
            state: state,
            ttlMilliseconds: stateTTLMilliseconds
        )
        await send(command)
    }

    public func setFinishedDuration(_ duration: TimeInterval) async {
        await reducer.setFinishedDuration(duration)
    }

    public func updateBrightness(_ value: UInt8) async {
        brightness = min(value, GeneratedAnimations.brightnessLimit)
        guard isConnected else { return }
        await send(.brightness(sequence: nextSequence(), value: isPaused ? 0 : brightness))
    }

    public func setPaused(_ paused: Bool) async {
        guard paused != isManuallyPaused else { return }
        isManuallyPaused = paused
        await applyPauseState()
    }

    public func setSystemSleepPaused(_ paused: Bool) async {
        guard paused != isPausedForSystemSleep else { return }
        isPausedForSystemSleep = paused
        await applyPauseState()
    }

    private func applyPauseState() async {
        let shouldPause = isManuallyPaused || isPausedForSystemSleep
        guard shouldPause != isPaused else { return }
        isPaused = shouldPause
        guard isConnected else { return }

        if shouldPause {
            await send(.brightness(sequence: nextSequence(), value: 0))
        } else {
            await send(.brightness(sequence: nextSequence(), value: brightness))
            await refreshStateLease()
        }
    }

    public func clearPresentationState() async {
        let snapshot = await reducer.clearPresentationState()
        await setReducedDisplayState(snapshot.displayState)
    }

    private func refreshStateLease() async {
        let state: DisplayState
        if followsReducer {
            let snapshot = await reducer.currentSnapshot()
            state = snapshot.displayState
        } else {
            state = displayState
        }

        displayState = state
        if isPaused {
            await send(.brightness(sequence: nextSequence(), value: 0))
        } else {
            await applyDisplayState(state)
        }
    }

    private func send(_ command: MatrixCommand) async {
        lastCommand = command.wireValue
        do {
            try await transport.send(command)
        } catch {
            lastResponse = error.localizedDescription
            isConnected = false
            connectionLabel = "Matrix disconnected"
        }
    }

    private func handleTransportEvent(_ event: MatrixTransportEvent) {
        switch event {
        case .searching:
            connectionLabel = "Searching for matrix"
        case let .connected(identity):
            isConnected = true
            firmwareVersion = identity.firmwareVersion
            hardwareID = identity.hardwareID
            connectionLabel = identity.hardwareID.hasPrefix("virtual-")
                ? "Simulator fallback"
                : "Physical matrix connected"
            Task {
                await updateBrightness(brightness)
                await applyDisplayState(displayState == .booting ? .idle : displayState)
            }
        case .disconnected:
            isConnected = false
            hardwareID = "-"
            connectionLabel = "Matrix disconnected"
        case let .response(response):
            lastResponse = response.wireValue
        case let .recoverableError(message), let .fatalError(message):
            lastResponse = message
        }
    }

    private func nextSequence() -> UInt32 {
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        return sequence
    }
}
