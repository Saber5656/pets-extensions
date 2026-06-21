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

    func testRejectsLengthGrowingEditBeforeInputEnd() {
        var session = TypingSession(exercise: exercise, now: 0)

        _ = session.update(rawInput: "ab", now: 1)
        let event = session.update(rawInput: "axb", now: 2)
        let metrics = session.metrics(at: 2)

        XCTAssertEqual(event, .idle)
        XCTAssertEqual(session.input, "ab")
        XCTAssertEqual(metrics.liveErrors, 0)
        XCTAssertEqual(metrics.totalTyped, 2)
        XCTAssertEqual(metrics.totalErrors, 0)
    }

    func testRejectsSelectionReplacementWithoutDelete() {
        var session = TypingSession(exercise: exercise, now: 0)

        _ = session.update(rawInput: "ax", now: 1)
        let event = session.update(rawInput: "ab", now: 2)
        let metrics = session.metrics(at: 2)

        XCTAssertEqual(event, .idle)
        XCTAssertEqual(session.input, "ax")
        XCTAssertEqual(metrics.liveErrors, 1)
        XCTAssertEqual(metrics.totalTyped, 2)
        XCTAssertEqual(metrics.totalErrors, 1)
    }

    func testCompletion() {
        var session = TypingSession(exercise: exercise, now: 0)

        let event = session.update(rawInput: "abcd", now: 12)

        XCTAssertEqual(event, .complete)
        XCTAssertEqual(session.completedAt, 12)
        XCTAssertTrue(session.metrics(at: 12).completed)
        XCTAssertEqual(session.metrics(at: 12).accuracy, 100)
    }

    func testBlankSubmissionDoesNotReceiveAccuracyScore() {
        let session = TypingSession(exercise: exercise, now: 0)
        let metrics = session.metrics(at: 10)

        XCTAssertEqual(typingScore(for: metrics), 0)
    }

    func testAccuracyScoreScalesWithProgress() {
        var partialSession = TypingSession(exercise: exercise, now: 0)
        var completeSession = TypingSession(exercise: exercise, now: 0)

        _ = partialSession.update(rawInput: "a", now: 10)
        _ = completeSession.update(rawInput: "abcd", now: 10)

        let partialScore = typingScore(for: partialSession.metrics(at: 10))
        let completeScore = typingScore(for: completeSession.metrics(at: 10))

        XCTAssertGreaterThan(partialScore, 0)
        XCTAssertLessThan(partialScore, completeScore)
    }

    func testFeedbackStates() {
        let states = feedback(for: "abcd", input: "ax").map(\.state)

        XCTAssertEqual(states, [.correct, .incorrect, .current, .pending])
    }

    func testDefaultExercisesProvideVariety() {
        let ids = Exercise.defaults.map(\.id)

        XCTAssertGreaterThanOrEqual(Exercise.defaults.count, 20)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

}
