import AgentMatrixCore
import AgentMatrixProtocol
import Foundation
import XCTest

final class AgentStateReducerTests: XCTestCase {
    func testAggregatePriorityAndFinishedExpiry() async {
        let reducer = AgentStateReducer(finishedDuration: 10)
        let base = Date(timeIntervalSince1970: 100)

        var snapshot = await reducer.receive(event(.turnStarted, session: "a", turn: "1", milliseconds: 100_000), now: base)
        XCTAssertEqual(snapshot.displayState, .working)

        snapshot = await reducer.receive(event(.approvalRequired, session: "b", turn: "2", milliseconds: 100_100), now: base)
        XCTAssertEqual(snapshot.displayState, .needsInput)

        _ = await reducer.receive(event(.turnFinished, session: "b", turn: "2", milliseconds: 100_200), now: base)
        snapshot = await reducer.currentSnapshot(now: base)
        XCTAssertEqual(snapshot.displayState, .working)

        _ = await reducer.receive(event(.turnFinished, session: "a", turn: "1", milliseconds: 100_300), now: base)
        snapshot = await reducer.currentSnapshot(now: base)
        XCTAssertEqual(snapshot.displayState, .finished)

        snapshot = await reducer.currentSnapshot(now: base.addingTimeInterval(11))
        XCTAssertEqual(snapshot.displayState, .idle)
    }

    func testOlderActivityDoesNotOverrideFinishedTurn() async {
        let reducer = AgentStateReducer()
        let stop = event(.turnFinished, session: "a", turn: "1", milliseconds: 2_000)
        _ = await reducer.receive(stop)

        let oldActivity = event(.activity, session: "a", turn: "1", milliseconds: 1_000)
        let snapshot = await reducer.receive(oldActivity)
        XCTAssertEqual(snapshot.displayState, .finished)
    }

    func testDuplicateEventIsIgnored() async {
        let reducer = AgentStateReducer()
        let id = UUID()
        let first = event(.turnStarted, session: "a", turn: "1", milliseconds: 1_000, id: id)
        _ = await reducer.receive(first)
        let duplicate = event(.turnFinished, session: "a", turn: "1", milliseconds: 2_000, id: id)
        let snapshot = await reducer.receive(duplicate)
        XCTAssertEqual(snapshot.displayState, .working)
    }

    private func event(
        _ lifecycle: AgentLifecycleEvent,
        session: String,
        turn: String,
        milliseconds: Int64,
        id: UUID = UUID()
    ) -> NormalizedAgentEvent {
        NormalizedAgentEvent(
            source: .codex,
            event: lifecycle,
            sessionID: session,
            turnID: turn,
            sentAtUnixMilliseconds: milliseconds,
            eventInstanceID: id
        )
    }
}
