import AgentMatrixProtocol
import Foundation

public enum RuntimeMatrixTarget: String, Equatable, Sendable {
    case automatic
    case hardware
    case simulator
}

public enum RuntimeMatrixDestination: Equatable, Sendable {
    case hardware
    case simulator
}

public actor RuntimeMatrixTransport: MatrixTransport {
    public nonisolated let events: AsyncStream<MatrixTransportEvent>

    private let simulator: any MatrixTransport
    private let hardware: any MatrixTransport
    private let continuation: AsyncStream<MatrixTransportEvent>.Continuation
    private let retryInterval: Duration
    private var target: RuntimeMatrixTarget
    private var destination: RuntimeMatrixDestination?
    private var simulatorIdentity: DeviceIdentity?
    private var hardwareIdentity: DeviceIdentity?
    private var simulatorEventTask: Task<Void, Never>?
    private var hardwareEventTask: Task<Void, Never>?
    private var hardwareRetryTask: Task<Void, Never>?
    private var hardwareConnectionInProgress = false
    private var hardwareDiscoveryPaused = false

    public init(
        simulator: any MatrixTransport,
        hardware: any MatrixTransport,
        target: RuntimeMatrixTarget = .automatic,
        retryInterval: Duration = .seconds(2)
    ) {
        self.simulator = simulator
        self.hardware = hardware
        self.target = target
        self.retryInterval = retryInterval
        let pair = AsyncStream.makeStream(of: MatrixTransportEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        simulatorEventTask?.cancel()
        hardwareEventTask?.cancel()
        hardwareRetryTask?.cancel()
    }

    public func connect() async {
        startEventListeners()
        await simulator.connect()
        if target != .simulator {
            startHardwareRetryLoop()
            await connectHardwareNow()
        }
    }

    public func disconnect() async {
        hardwareDiscoveryPaused = true
        hardwareRetryTask?.cancel()
        hardwareRetryTask = nil
        await hardware.disconnect()
        await simulator.disconnect()
        destination = nil
        hardwareIdentity = nil
        simulatorIdentity = nil
        continuation.yield(.disconnected)
    }

    public func send(_ command: MatrixCommand) async throws {
        let selectedDestination = destination
        do {
            try await simulator.send(command)
        } catch {
            if selectedDestination == .simulator { throw error }
        }

        switch selectedDestination {
        case .hardware:
            do {
                try await hardware.send(command)
            } catch {
                hardwareIdentity = nil
                if target == .automatic, simulatorIdentity != nil {
                    activateSimulator()
                    startHardwareRetryLoop()
                    return
                }
                throw error
            }
        case .simulator:
            return
        case nil:
            throw RuntimeMatrixTransportError.noActiveDisplay
        }
    }

    public func setTarget(_ newTarget: RuntimeMatrixTarget) async {
        guard newTarget != target else {
            if newTarget != .simulator { await connectHardwareNow() }
            return
        }

        target = newTarget
        switch newTarget {
        case .simulator:
            hardwareRetryTask?.cancel()
            hardwareRetryTask = nil
            await hardware.disconnect()
            hardwareIdentity = nil
            activateSimulator()
        case .automatic:
            if hardwareIdentity != nil {
                activateHardware()
            } else {
                activateSimulator()
            }
            startHardwareRetryLoop()
            await connectHardwareNow()
        case .hardware:
            if hardwareIdentity != nil {
                activateHardware()
            } else {
                destination = nil
                continuation.yield(.disconnected)
                continuation.yield(.searching)
            }
            startHardwareRetryLoop()
            await connectHardwareNow()
        }
    }

    public func activeDestination() -> RuntimeMatrixDestination? {
        destination
    }

    public func connectHardwareNow() async {
        guard target != .simulator else { return }
        await probeHardware()
    }

    public func probeHardware() async {
        guard !hardwareDiscoveryPaused, hardwareIdentity == nil, !hardwareConnectionInProgress else { return }
        hardwareConnectionInProgress = true
        await hardware.connect()
        hardwareConnectionInProgress = false
    }

    public func setHardwareDiscoveryPaused(_ paused: Bool) async {
        hardwareDiscoveryPaused = paused
        if paused {
            hardwareRetryTask?.cancel()
            hardwareRetryTask = nil
        } else if target != .simulator {
            startHardwareRetryLoop()
            await connectHardwareNow()
        }
    }

    private func startEventListeners() {
        if simulatorEventTask == nil {
            simulatorEventTask = Task { [weak self, stream = simulator.events] in
                for await event in stream {
                    guard !Task.isCancelled else { return }
                    await self?.handleSimulatorEvent(event)
                }
            }
        }
        if hardwareEventTask == nil {
            hardwareEventTask = Task { [weak self, stream = hardware.events] in
                for await event in stream {
                    guard !Task.isCancelled else { return }
                    await self?.handleHardwareEvent(event)
                }
            }
        }
    }

    private func startHardwareRetryLoop() {
        guard target != .simulator, !hardwareDiscoveryPaused, hardwareRetryTask == nil else { return }
        hardwareRetryTask = Task { [weak self, retryInterval] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.connectHardwareNow()
                try? await Task.sleep(for: retryInterval)
            }
        }
    }

    private func handleSimulatorEvent(_ event: MatrixTransportEvent) {
        switch event {
        case let .connected(identity):
            simulatorIdentity = identity
            if target == .simulator || target == .automatic && hardwareIdentity == nil {
                activateSimulator()
            }
        case .disconnected:
            simulatorIdentity = nil
            if destination == .simulator {
                destination = nil
                continuation.yield(.disconnected)
            }
        case let .response(response):
            if destination == .simulator { continuation.yield(.response(response)) }
        case .searching:
            if target == .simulator { continuation.yield(.searching) }
        case let .recoverableError(message):
            if destination == .simulator { continuation.yield(.recoverableError(message)) }
        case let .fatalError(message):
            if destination == .simulator { continuation.yield(.fatalError(message)) }
        }
    }

    private func handleHardwareEvent(_ event: MatrixTransportEvent) {
        switch event {
        case let .connected(identity):
            hardwareIdentity = identity
            if target != .simulator { activateHardware() }
        case .disconnected:
            hardwareIdentity = nil
            if destination == .hardware {
                if target == .automatic, simulatorIdentity != nil {
                    activateSimulator()
                } else {
                    destination = nil
                    continuation.yield(.disconnected)
                }
            }
            startHardwareRetryLoop()
        case let .response(response):
            if destination == .hardware { continuation.yield(.response(response)) }
        case .searching:
            if target == .hardware || destination == nil { continuation.yield(.searching) }
        case let .recoverableError(message):
            if target == .hardware || destination == .hardware {
                continuation.yield(.recoverableError(message))
            }
        case let .fatalError(message):
            if target == .hardware || destination == .hardware {
                continuation.yield(.fatalError(message))
            }
        }
    }

    private func activateSimulator() {
        guard let simulatorIdentity, destination != .simulator else { return }
        destination = .simulator
        continuation.yield(.connected(simulatorIdentity))
    }

    private func activateHardware() {
        guard let hardwareIdentity, destination != .hardware else { return }
        destination = .hardware
        continuation.yield(.connected(hardwareIdentity))
    }
}

public enum RuntimeMatrixTransportError: LocalizedError, Sendable {
    case noActiveDisplay

    public var errorDescription: String? {
        "No matrix display is connected."
    }
}
