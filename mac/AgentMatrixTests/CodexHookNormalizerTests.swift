import AgentMatrixCore
import AgentMatrixProtocol
import Foundation
import XCTest

final class CodexHookNormalizerTests: XCTestCase {
    func testNormalizerKeepsOnlyLifecycleMetadata() throws {
        let input = Data(#"""
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "session-1",
          "turn_id": "turn-2",
          "cwd": "/tmp/project",
          "tool_name": "Bash",
          "prompt": "private prompt",
          "tool_input": {"command": "secret"},
          "tool_output": "private output"
        }
        """#.utf8)

        let event = try CodexHookNormalizer.normalize(input, now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(event.event, .approvalRequired)
        XCTAssertEqual(event.sessionID, "session-1")
        XCTAssertEqual(event.turnID, "turn-2")
        XCTAssertEqual(event.toolName, "Bash")

        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private prompt"))
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("private output"))
    }

    func testOversizedInputIsRejected() {
        let input = Data(repeating: 0, count: CodexHookNormalizer.maximumInputBytes + 1)
        XCTAssertThrowsError(try CodexHookNormalizer.normalize(input))
    }
}
