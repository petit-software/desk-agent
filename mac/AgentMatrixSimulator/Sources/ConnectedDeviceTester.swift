import AgentMatrixCore
import AgentMatrixProtocol
import Combine
import Foundation

@MainActor
public final class ConnectedDeviceTester: ObservableObject {
    @Published public private(set) var isConnected = false
    @Published public private(set) var isConnecting = false
    @Published public private(set) var connectionLabel = "Not connected"
    @Published public private(set) var devicePath = "No compatible device"
    @Published public private(set) var firmwareVersion = "-"
    @Published public private(set) var hardwareID = "-"
    @Published public private(set) var lastResponse = "No response"
    @Published public private(set) var firmwareFlashPhase = FirmwareFlashPhase.ready
    @Published public private(set) var firmwareFlashMessage = "Install the bundled DeskAgent firmware over USB."

    private let transport: SerialMatrixTransport
    private var sequence: UInt32 = 0
    private var heartbeatTask: Task<Void, Never>?
    private var firmwareFlashTask: Task<Void, Never>?
    private let firmwareFlasher: UF2FirmwareFlasher
    private let firmwareURL: @Sendable () -> URL?
    private let runtimeTransport: RuntimeMatrixTransport?
    private let managesHeartbeat: Bool

    public init(
        transport: SerialMatrixTransport = SerialMatrixTransport(),
        runtimeTransport: RuntimeMatrixTransport? = nil,
        managesHeartbeat: Bool = true,
        firmwareFlasher: UF2FirmwareFlasher = UF2FirmwareFlasher(),
        firmwareURL: @escaping @Sendable () -> URL? = {
            Bundle.main.url(forResource: "DeskAgent", withExtension: "uf2")
        }
    ) {
        self.transport = transport
        self.runtimeTransport = runtimeTransport
        self.managesHeartbeat = managesHeartbeat
        self.firmwareFlasher = firmwareFlasher
        self.firmwareURL = firmwareURL
    }

    deinit {
        heartbeatTask?.cancel()
        firmwareFlashTask?.cancel()
    }

    public func connect(state: DisplayState, brightness: UInt8) async {
        heartbeatTask?.cancel()
        isConnecting = true
        isConnected = false
        connectionLabel = "Searching for DeskAgent firmware"
        if await transport.connectionInfo() == nil {
            if let runtimeTransport {
                await runtimeTransport.probeHardware()
            } else {
                await transport.connect()
            }
        }

        guard let info = await transport.connectionInfo() else {
            connectionLabel = await transport.latestDiscoveryMessage()
            devicePath = SerialPortDiscovery.calloutDevices().first ?? "No USB serial device"
            firmwareVersion = "-"
            hardwareID = "-"
            isConnecting = false
            return
        }

        isConnected = true
        isConnecting = false
        connectionLabel = "Connected"
        devicePath = info.path
        firmwareVersion = info.identity.firmwareVersion
        hardwareID = info.identity.hardwareID
        await send(.brightness(sequence: nextSequence(), value: brightness))
        await send(.state(sequence: nextSequence(), state: state, ttlMilliseconds: 8_000))
        let runtimeUsesHardware = await runtimeTransport?.activeDestination() == .hardware
        if managesHeartbeat || !runtimeUsesHardware { startHeartbeat() }
    }

    public func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if runtimeTransport == nil { await transport.disconnect() }
        isConnected = false
        isConnecting = false
        connectionLabel = "Not connected"
    }

    public func sendState(_ state: DisplayState) async {
        guard isConnected else { return }
        if await runtimeTransport?.activeDestination() == .hardware { return }
        await send(.state(sequence: nextSequence(), state: state, ttlMilliseconds: 8_000))
    }

    public func identify() async {
        guard isConnected else { return }
        await send(.identify(sequence: nextSequence()))
    }

    public func startFirmwareFlash(state: DisplayState, brightness: UInt8) {
        guard firmwareFlashTask == nil else { return }
        firmwareFlashTask = Task { [weak self] in
            await self?.performFirmwareFlash(state: state, brightness: brightness)
        }
    }

    public func cancelFirmwareFlash() {
        guard firmwareFlashTask != nil else { return }
        firmwareFlashTask?.cancel()
        firmwareFlashTask = nil
        firmwareFlashPhase = .ready
        firmwareFlashMessage = "Firmware installation cancelled."
    }

    private func performFirmwareFlash(state: DisplayState, brightness: UInt8) async {
        var runtimeDiscoveryPaused = false
        defer { firmwareFlashTask = nil }
        do {
            guard let firmwareURL = firmwareURL() else {
                throw FirmwareFlashWorkflowError.missingBundledFirmware
            }
            try firmwareFlasher.validateFirmware(at: firmwareURL)
            if let runtimeTransport {
                await runtimeTransport.setHardwareDiscoveryPaused(true)
                runtimeDiscoveryPaused = true
            }
            await transport.disconnect()
            isConnected = false
            connectionLabel = "Not connected"

            var volume = firmwareFlasher.bootloaderVolume()
            if volume == nil {
                firmwareFlashPhase = .waitingForBootloader
                firmwareFlashMessage = "Hold BOOT, press and release RESET, then release BOOT. Waiting for RPI-RP2..."
            }

            let waitingDeadline = Date().addingTimeInterval(120)
            while volume == nil, Date() < waitingDeadline {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(400))
                volume = firmwareFlasher.bootloaderVolume()
            }
            try Task.checkCancellation()
            guard let volume else { throw FirmwareFlashWorkflowError.bootloaderTimedOut }

            firmwareFlashPhase = .flashing
            firmwareFlashMessage = "Copying validated firmware to the Pico..."
            try firmwareFlasher.flash(firmwareURL: firmwareURL, to: volume)

            firmwareFlashPhase = .restarting
            firmwareFlashMessage = "Firmware copied. Waiting for DeskAgent to restart..."
            try await Task.sleep(for: .seconds(2))

            if let runtimeTransport {
                await runtimeTransport.setHardwareDiscoveryPaused(false)
                runtimeDiscoveryPaused = false
            }

            for _ in 0..<6 where !isConnected {
                try Task.checkCancellation()
                await connect(state: state, brightness: brightness)
                if !isConnected {
                    try await Task.sleep(for: .seconds(1))
                }
            }

            if isConnected {
                firmwareFlashPhase = .succeeded
                firmwareFlashMessage = "Firmware installed and AM1 connection verified."
            } else {
                throw FirmwareFlashWorkflowError.reconnectFailed
            }
        } catch is CancellationError {
            if runtimeDiscoveryPaused {
                await runtimeTransport?.setHardwareDiscoveryPaused(false)
            }
            firmwareFlashPhase = .ready
            firmwareFlashMessage = "Firmware installation cancelled."
        } catch {
            if runtimeDiscoveryPaused {
                await runtimeTransport?.setHardwareDiscoveryPaused(false)
            }
            firmwareFlashPhase = .failed
            firmwareFlashMessage = error.localizedDescription
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isConnected, !Task.isCancelled else { return }
                await self.send(.ping(sequence: self.nextSequence()))
            }
        }
    }

    private func send(_ command: MatrixCommand) async {
        do {
            try await transport.send(command)
            if let sequence = command.sequence {
                lastResponse = MatrixResponse.acknowledgement(sequence: sequence).wireValue
            }
        } catch {
            lastResponse = error.localizedDescription
        }
    }

    private func nextSequence() -> UInt32 {
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        return sequence
    }
}

public enum FirmwareFlashPhase: Equatable, Sendable {
    case ready
    case waitingForBootloader
    case flashing
    case restarting
    case succeeded
    case failed

    public var isActive: Bool {
        switch self {
        case .waitingForBootloader, .flashing, .restarting: true
        case .ready, .succeeded, .failed: false
        }
    }
}

private enum FirmwareFlashWorkflowError: LocalizedError {
    case missingBundledFirmware
    case bootloaderTimedOut
    case reconnectFailed

    var errorDescription: String? {
        switch self {
        case .missingBundledFirmware:
            "This build does not contain DeskAgent.uf2. Rebuild the app with the firmware resource."
        case .bootloaderTimedOut:
            "RPI-RP2 did not appear. Put the board in BOOTSEL mode and try again."
        case .reconnectFailed:
            "Firmware was copied, but DeskAgent did not reconnect. Unplug the board, reconnect it, and retry."
        }
    }
}
