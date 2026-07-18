import AgentMatrixCore
import AgentMatrixSimulator
import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    let transport: SimulatorMatrixTransport
    let coordinator: MatrixCoordinator
    let preferences: AppPreferences
    @Published private(set) var integrationStatus: CodexIntegrationStatus = .notInstalled
    @Published private(set) var integrationMessage: String?
    private let eventServer = AgentEventServer()
    private let integrationInstaller = CodexIntegrationInstaller()
    private var started = false

    init() {
        let transport = SimulatorMatrixTransport()
        self.transport = transport
        coordinator = MatrixCoordinator(transport: transport)
        preferences = AppPreferences()
        integrationStatus = integrationInstaller.status()
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
            integrationMessage = "Run /hooks in Codex and review the Agent Matrix command."
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
}
