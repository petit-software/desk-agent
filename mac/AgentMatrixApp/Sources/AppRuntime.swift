import AgentMatrixCore
import AgentMatrixSimulator
import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    let transport: SimulatorMatrixTransport
    let serialTransport: SerialMatrixTransport
    let matrixTransport: RuntimeMatrixTransport
    let connectedDeviceTester: ConnectedDeviceTester
    let coordinator: MatrixCoordinator
    let preferences: AppPreferences
    @Published private(set) var integrationStatus: CodexIntegrationStatus = .notInstalled
    @Published private(set) var integrationMessage: String?
    private let eventServer = AgentEventServer()
    private let integrationInstaller = CodexIntegrationInstaller()
    private var started = false
    private var displayTargetCancellable: AnyCancellable?
    private var finishedDurationCancellable: AnyCancellable?

    init() {
        let transport = SimulatorMatrixTransport()
        let serialTransport = SerialMatrixTransport()
        let preferences = AppPreferences()
        let matrixTransport = RuntimeMatrixTransport(
            simulator: transport,
            hardware: serialTransport,
            target: Self.runtimeTarget(for: preferences.displayTarget)
        )
        self.transport = transport
        self.serialTransport = serialTransport
        self.matrixTransport = matrixTransport
        self.preferences = preferences
        connectedDeviceTester = ConnectedDeviceTester(
            transport: serialTransport,
            runtimeTransport: matrixTransport,
            managesHeartbeat: false
        )
        let coordinator = MatrixCoordinator(
            transport: matrixTransport,
            reducer: AgentStateReducer(finishedDuration: preferences.finishedDuration)
        )
        self.coordinator = coordinator
        integrationStatus = integrationInstaller.status()
        displayTargetCancellable = preferences.$displayTarget
            .removeDuplicates()
            .sink { target in
                Task { await matrixTransport.setTarget(Self.runtimeTarget(for: target)) }
            }
        finishedDurationCancellable = preferences.$finishedDuration
            .removeDuplicates()
            .sink { duration in
                Task { await coordinator.setFinishedDuration(duration) }
            }
    }

    func start() {
        guard !started else { return }
        started = true
        coordinator.start()
        do {
            try eventServer.start { [weak self] event in
                Task { @MainActor [weak self] in await self?.coordinator.receive(event) }
            }
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func stop() {
        started = false
        eventServer.stop()
        coordinator.stop()
    }

    func installIntegration() {
        guard let helperURL = Bundle.main.url(forResource: "agent-matrix-hook", withExtension: nil) else {
            integrationMessage = CodexIntegrationError.bundledHelperMissing.localizedDescription
            return
        }
        do {
            _ = try integrationInstaller.install(bundledHelperURL: helperURL)
            integrationStatus = .needsTrustReview
            integrationMessage = "Run /hooks in Codex and review the DeskAgent command."
        } catch {
            integrationStatus = integrationInstaller.status()
            integrationMessage = error.localizedDescription
        }
    }

    func removeIntegration() {
        do {
            _ = try integrationInstaller.uninstall()
            integrationStatus = .notInstalled
            integrationMessage = nil
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    private static func runtimeTarget(for target: AppPreferences.DisplayTarget) -> RuntimeMatrixTarget {
        switch target {
        case .automatic: .automatic
        case .hardware: .hardware
        case .simulator: .simulator
        }
    }
}
