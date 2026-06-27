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

final class ConversationEngineTests: XCTestCase {
    func testConversationHistoryKeepsRecentExchanges() {
        var session = ConversationSession(maxExchangeCount: 2)

        session.recordUserMessage("one")
        session.recordPetMessage("two")
        session.recordUserMessage("three")
        session.recordPetMessage("four")
        session.recordUserMessage("five")
        session.recordPetMessage("six")

        XCTAssertEqual(session.recentMessages.map(\.text), ["three", "four", "five", "six"])
    }

    func testUnsupportedRequestDetection() {
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "明日10時にリマインドして"), .reminder)
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "Safariを開いて"), .codexHandoff)
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "Safariを操作して"), .codexHandoff)
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "Obsidianに入力して"), .codexHandoff)
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "このPRをレビューして"), .codexHandoff)
        XCTAssertEqual(ConversationPolicy.unsupportedRequest(in: "Macを再起動して"), .osOperation)
        XCTAssertNil(ConversationPolicy.unsupportedRequest(in: "この映画をレビューして"))
    }

    func testResponseNormalizationLimitsSentences() {
        let response = ConversationResponseNormalizer.normalize(
            "  いいよ。  \n\n\n少し休もう。さらに話すね。",
            maxSentences: 2
        )

        XCTAssertEqual(response, "いいよ。\n\n少し休もう。")
    }

    func testClearReminderRequestParses() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 27,
            hour: 9,
            minute: 0
        )))

        let result = ReminderParser.parse(
            "明日午前10時に牛乳を買うのをリマインドして",
            now: now,
            calendar: calendar
        )

        guard case .ready(let reminder) = result else {
            XCTFail("Expected a ready reminder request")
            return
        }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dueDate
        )
        XCTAssertTrue(reminder.title.contains("牛乳"))
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 0)
    }

    func testAmbiguousReminderRequestsAskForClarification() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 27,
            hour: 9,
            minute: 0
        )))

        XCTAssertEqual(
            ReminderParser.parse("10時にリマインドして", now: now, calendar: calendar),
            .needsClarification("いつのリマインダーにする？日付と時刻を入れてね。")
        )
        XCTAssertEqual(
            ReminderParser.parse("明日リマインドして", now: now, calendar: calendar),
            .needsClarification("何時にリマインドする？日付と時刻を入れてね。")
        )
        XCTAssertEqual(
            ReminderParser.parse("明日10時にリマインドして", now: now, calendar: calendar),
            .needsClarification("午前か午後も教えてね。")
        )
        XCTAssertTrue(ReminderParser.isUndoRequest("取り消して"))
        XCTAssertTrue(ReminderParser.isCancellationReply("キャンセル"))
        XCTAssertFalse(ReminderParser.isUndoRequest("キャンセル"))
    }

    func testReminderClarificationMergesIntoPendingRequest() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 27,
            hour: 9,
            minute: 0
        )))

        let mergedInput = try XCTUnwrap(ReminderParser.mergeClarification(
            pendingInput: "明日10時に牛乳を買うのをリマインドして",
            reply: "午後"
        ))
        let result = ReminderParser.parse(mergedInput, now: now, calendar: calendar)

        guard case .ready(let reminder) = result else {
            XCTFail("Expected a clarified reminder request")
            return
        }
        let components = calendar.dateComponents([.hour, .minute], from: reminder.dueDate)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 0)
        XCTAssertTrue(reminder.title.contains("牛乳"))
    }

    func testColonTimeWithPMMarkerParsesAsAfternoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 27,
            hour: 9,
            minute: 0
        )))

        let result = ReminderParser.parse(
            "明日午後10:30に牛乳を買うのをリマインドして",
            now: now,
            calendar: calendar
        )

        guard case .ready(let reminder) = result else {
            XCTFail("Expected a ready reminder request")
            return
        }
        let components = calendar.dateComponents([.hour, .minute], from: reminder.dueDate)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 30)
    }

    func testCodexHandoffPlanKeepsImmediateRequest() {
        let plan = CodexHandoffPlanner.plan(
            for: "このrepoのテスト失敗を調査して",
            recentMessages: [
                ConversationMessage(speaker: .user, text: "前の会話"),
                ConversationMessage(speaker: .pet, text: "うん")
            ]
        )

        XCTAssertEqual(plan?.category, .research)
        XCTAssertEqual(plan?.summary, "調査・要約としてCodexに引き継ぐ: このrepoのテスト失敗を調査して")
        XCTAssertEqual(CodexHandoffPlanner.isConfirmation("はい"), true)
        XCTAssertEqual(CodexHandoffPlanner.isCancellation("やめて"), true)
        XCTAssertEqual(plan?.taskText.contains("このrepoのテスト失敗を調査して"), true)
        XCTAssertEqual(plan?.taskText.contains("前の会話"), false)
        XCTAssertEqual(
            CodexHandoffPlanner.plan(for: "この映画をレビューして", recentMessages: []) == nil,
            true
        )
    }

    func testAppLaunchRequestsAreComputerUseHandoffs() {
        let appLaunchPlan = CodexHandoffPlanner.plan(for: "Obsidianを起動して", recentMessages: [])
        let appInputPlan = CodexHandoffPlanner.plan(for: "Obsidianに入力して", recentMessages: [])

        XCTAssertEqual(appLaunchPlan?.category, .computerUse)
        XCTAssertEqual(appInputPlan?.category, .computerUse)
        XCTAssertEqual(
            appLaunchPlan?.summary,
            "Computer Useを含む可能性がある作業としてCodexに引き継ぐ: Obsidianを起動して"
        )
        XCTAssertEqual(appLaunchPlan?.taskText.contains("Obsidianを起動して"), true)
        XCTAssertEqual(appInputPlan?.taskText.contains("Obsidianに入力して"), true)
    }
}
