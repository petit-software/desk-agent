import AgentMatrixCore
import Foundation
import XCTest

final class CodexIntegrationInstallerTests: XCTestCase {
    func testInstallPreservesHooksAndIsIdempotent() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = CodexIntegrationInstaller(homeDirectory: home)
        let codexDirectory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "custom": "preserve-me",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/usr/bin/existing", "timeout": 5]]]]]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.configurationURL)
        let helper = home.appendingPathComponent("bundled-helper")
        try Data("helper".utf8).write(to: helper)

        _ = try installer.install(bundledHelperURL: helper)
        _ = try installer.install(bundledHelperURL: helper)

        let data = try Data(contentsOf: installer.configurationURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["custom"] as? String, "preserve-me")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 2)
        XCTAssertEqual(installer.status(), .installed)
    }

    func testMalformedConfigurationIsNeverOverwritten() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = CodexIntegrationInstaller(homeDirectory: home)
        try FileManager.default.createDirectory(at: installer.configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: installer.configurationURL)
        let helper = home.appendingPathComponent("bundled-helper")
        try Data("helper".utf8).write(to: helper)

        XCTAssertThrowsError(try installer.install(bundledHelperURL: helper))
        XCTAssertEqual(try Data(contentsOf: installer.configurationURL), malformed)
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AgentMatrixTests-\(UUID().uuidString)")
    }
}
