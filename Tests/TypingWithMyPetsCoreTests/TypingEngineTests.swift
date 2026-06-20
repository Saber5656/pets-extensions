import XCTest
@testable import TypingWithMyPetsCore

final class TypingEngineTests: XCTestCase {
    private let exercise = Exercise(id: "sample", title: "Sample", text: "abcd")

    func testCorrectProgress() {
        var session = TypingSession(exercise: exercise, now: 0)

        let event = session.update(rawInput: "ab", now: 30)
        let metrics = session.metrics(at: 30)

        XCTAssertEqual(event, .correct)
        XCTAssertEqual(session.input, "ab")
        XCTAssertEqual(session.correctStreak, 2)
        XCTAssertEqual(metrics.liveErrors, 0)
        XCTAssertEqual(metrics.progress, 0.5)
        XCTAssertEqual(Int(metrics.wpm.rounded()), 1)
    }

    func testMistakePersistsInTotalAccuracyAfterDelete() {
        var session = TypingSession(exercise: exercise, now: 0)

        _ = session.update(rawInput: "ax", now: 1)
        let event = session.update(rawInput: "a", now: 2)
        let metrics = session.metrics(at: 2)

        XCTAssertEqual(event, .delete)
        XCTAssertEqual(session.input, "a")
        XCTAssertEqual(metrics.liveErrors, 0)
        XCTAssertEqual(metrics.totalErrors, 1)
        XCTAssertEqual(Int(metrics.accuracy.rounded()), 50)
    }

    func testCompletion() {
        var session = TypingSession(exercise: exercise, now: 0)

        let event = session.update(rawInput: "abcd", now: 12)

        XCTAssertEqual(event, .complete)
        XCTAssertEqual(session.completedAt, 12)
        XCTAssertTrue(session.metrics(at: 12).completed)
        XCTAssertEqual(session.metrics(at: 12).accuracy, 100)
    }

    func testFeedbackStates() {
        let states = feedback(for: "abcd", input: "ax").map(\.state)

        XCTAssertEqual(states, [.correct, .incorrect, .current, .pending])
    }

}
