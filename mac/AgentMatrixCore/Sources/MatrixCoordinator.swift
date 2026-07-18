import AgentMatrixProtocol
import Combine
import Foundation

@MainActor
public final class MatrixCoordinator: ObservableObject {
    @Published public private(set) var displayState: DisplayState = .booting
    @Published public private(set) var connectionLabel = "Starting simulator"
    @Published public private(set) var isConnected = false
    @Published public private(set) var lastCommand = "AM1 HELLO"
    @Published public private(set) var lastResponse = "Waiting for virtual device"
    @Published public private(set) var firmwareVersion = "-"
    @Published public private(set) var lastEvent: NormalizedAgentEvent?
    @Published public var brightness: UInt8 = GeneratedAnimations.brightnessLimit

    public let reducer: AgentStateReducer
    private let transport: any MatrixTransport
    private var sequence: UInt32 = 0
    private var eventTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    public init(transport: any MatrixTransport, reducer: AgentStateReducer = AgentStateReducer()) {
        self.transport = transport
        self.reducer = reducer
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
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isConnected else { continue }
                await self.sendHeartbeat()
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
        await setDisplayState(snapshot.displayState)
    }

    public func setDisplayState(_ state: DisplayState) async {
        displayState = state
        guard isConnected else { return }
        let command = MatrixCommand.state(sequence: nextSequence(), state: state, ttlMilliseconds: 8_000)
        await send(command)
    }

    public func updateBrightness(_ value: UInt8) async {
        brightness = min(value, GeneratedAnimations.brightnessLimit)
        guard isConnected else { return }
        await send(.brightness(sequence: nextSequence(), value: brightness))
    }

    public func clearPresentationState() async {
        let snapshot = await reducer.clearPresentationState()
        await setDisplayState(snapshot.displayState)
    }

    private func sendHeartbeat() async {
        await send(.ping(sequence: nextSequence()))
    }

    private func send(_ command: MatrixCommand) async {
        lastCommand = command.wireValue
        do {
            try await transport.send(command)
        } catch {
            lastResponse = error.localizedDescription
            isConnected = false
            connectionLabel = "Simulator disconnected"
        }
    }

    private func handleTransportEvent(_ event: MatrixTransportEvent) {
        switch event {
        case .searching:
            connectionLabel = "Searching for matrix"
        case let .connected(identity):
            isConnected = true
            firmwareVersion = identity.firmwareVersion
            connectionLabel = "Simulator connected"
            Task {
                await updateBrightness(brightness)
                await setDisplayState(displayState == .booting ? .idle : displayState)
            }
        case .disconnected:
            isConnected = false
            connectionLabel = "Simulator disconnected"
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
