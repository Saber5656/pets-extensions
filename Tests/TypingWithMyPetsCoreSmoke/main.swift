import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let exercise = Exercise(id: "sample", title: "Sample", text: "abcd")
var session = TypingSession(exercise: exercise, now: 0)
let event = session.update(rawInput: "ab", now: 30)
let metrics = session.metrics(at: 30)

expect(event == .correct, "event should be correct")
expect(session.correctStreak == 2, "streak should be 2")
expect(metrics.liveErrors == 0, "live errors should be 0")
expect(metrics.progress == 0.5, "progress should be 0.5")

_ = session.update(rawInput: "abx", now: 31)
_ = session.update(rawInput: "ab", now: 32)
expect(session.metrics(at: 32).totalErrors == 1, "deleted mistakes remain counted")

var appendOnlySession = TypingSession(exercise: exercise, now: 0)
_ = appendOnlySession.update(rawInput: "ab", now: 1)
_ = appendOnlySession.update(rawInput: "axb", now: 2)
expect(appendOnlySession.input == "ab", "mid-string insertion should be rejected")
expect(appendOnlySession.metrics(at: 2).totalErrors == 0, "rejected edit should not affect scoring")

let states = feedback(for: "abcd", input: "ax").map(\.state)
expect(states == [.correct, .incorrect, .current, .pending], "feedback states should match")

let blankMetrics = TypingSession(exercise: exercise, now: 0).metrics(at: 10)
expect(typingScore(for: blankMetrics) == 0, "blank input should not receive accuracy score")

let defaultExerciseIDs = Exercise.defaults.map(\.id)
expect(Exercise.defaults.count >= 20, "default exercises should provide enough variety")
expect(Set(defaultExerciseIDs).count == defaultExerciseIDs.count, "default exercise ids should be unique")

var conversation = ConversationSession(maxExchangeCount: 2)
conversation.recordUserMessage("one")
conversation.recordPetMessage("two")
conversation.recordUserMessage("three")
conversation.recordPetMessage("four")
conversation.recordUserMessage("five")
conversation.recordPetMessage("six")
expect(conversation.recentMessages.map(\.text) == ["three", "four", "five", "six"], "conversation history should keep recent exchanges")

expect(
    ConversationPolicy.unsupportedRequest(in: "明日10時にリマインドして") == .reminder,
    "reminder requests should be unsupported in phase 1"
)
expect(
    ConversationPolicy.unsupportedRequest(in: "VS Codeを開いて") == .codexHandoff,
    "app launch requests should be delegated through Codex handoff"
)
expect(
    ConversationPolicy.unsupportedRequest(in: "Obsidianに入力して") == .codexHandoff,
    "GUI input requests should be delegated through Codex handoff"
)
expect(
    ConversationPolicy.unsupportedRequest(in: "Macを再起動して") == .osOperation,
    "dangerous OS lifecycle requests should stay unsupported"
)
expect(
    ConversationResponseNormalizer.normalize("  いいよ。  \n\n\n少し休もう。さらに話すね。", maxSentences: 2) == "いいよ。\n\n少し休もう。",
    "conversation responses should be compacted and sentence-limited"
)
expect(
    ConversationPolicy.unsupportedRequest(in: "この映画をレビューして") == nil,
    "ordinary review conversation should not be forced into Codex handoff"
)

var reminderCalendar = Calendar(identifier: .gregorian)
reminderCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let reminderNow = reminderCalendar.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 9, minute: 0))!
let reminderResult = ReminderParser.parse(
    "明日午前10時に牛乳を買うのをリマインドして",
    now: reminderNow,
    calendar: reminderCalendar
)
if case .ready(let reminder) = reminderResult {
    let components = reminderCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueDate)
    expect(reminder.title.contains("牛乳"), "reminder title should preserve the task")
    expect(components.year == 2026, "reminder year should be parsed")
    expect(components.month == 6, "reminder month should be parsed")
    expect(components.day == 28, "relative reminder day should be parsed")
    expect(components.hour == 10, "reminder hour should be parsed")
    expect(components.minute == 0, "reminder minute should default to zero")
} else {
    expect(false, "clear reminder requests should parse")
}
expect(
    ReminderParser.parse("10時にリマインドして", now: reminderNow, calendar: reminderCalendar)
        == .needsClarification("いつのリマインダーにする？日付と時刻を入れてね。"),
    "reminders without a date should ask for clarification"
)
expect(
    ReminderParser.parse("明日10時にリマインドして", now: reminderNow, calendar: reminderCalendar)
        == .needsClarification("午前か午後も教えてね。"),
    "bare 1-12 hour reminder requests should ask for AM/PM clarification"
)
let mergedReminderInput = ReminderParser.mergeClarification(
    pendingInput: "明日10時に牛乳を買うのをリマインドして",
    reply: "午後"
)
expect(mergedReminderInput != nil, "AM/PM clarification should merge into pending reminder input")
let clarifiedReminderResult = ReminderParser.parse(
    mergedReminderInput ?? "",
    now: reminderNow,
    calendar: reminderCalendar
)
if case .ready(let clarifiedReminder) = clarifiedReminderResult {
    let components = reminderCalendar.dateComponents([.hour, .minute], from: clarifiedReminder.dueDate)
    expect(components.hour == 22, "PM clarification should refine a bare hour")
    expect(components.minute == 0, "clarified reminder minute should default to zero")
} else {
    expect(false, "clarified reminder should parse")
}
let colonPMResult = ReminderParser.parse(
    "明日午後10:30に牛乳を買うのをリマインドして",
    now: reminderNow,
    calendar: reminderCalendar
)
if case .ready(let colonPMReminder) = colonPMResult {
    let components = reminderCalendar.dateComponents([.hour, .minute], from: colonPMReminder.dueDate)
    expect(components.hour == 22, "PM marker should refine colon time hours")
    expect(components.minute == 30, "colon time minutes should be preserved")
} else {
    expect(false, "colon PM reminder should parse")
}
expect(
    ReminderParser.isUndoRequest("取り消して"),
    "reminder undo wording should be detected"
)
expect(
    ReminderParser.isCancellationReply("キャンセル"),
    "pending reminder cancellation wording should be detected separately from undo"
)
expect(
    !ReminderParser.isUndoRequest("キャンセル"),
    "generic cancellation should not delete the last reminder"
)

let codexPlan = CodexHandoffPlanner.plan(
    for: "このrepoのテスト失敗を調査して",
    recentMessages: conversation.recentMessages
)
expect(codexPlan?.category == .research, "research handoff should be categorized")
expect(codexPlan?.taskText.contains("このrepoのテスト失敗を調査して") == true, "handoff task should include the immediate request")
expect(codexPlan?.taskText.contains("three") == false, "handoff task should not include raw conversation history")
expect(CodexHandoffPlanner.isConfirmation("はい"), "handoff confirmation should be detected")

let appLaunchPlan = CodexHandoffPlanner.plan(for: "Obsidianを起動して", recentMessages: [])
expect(appLaunchPlan?.category == .computerUse, "app launch requests should be computer-use handoffs")
expect(appLaunchPlan?.taskText.contains("Obsidianを起動して") == true, "app launch handoff should include the immediate request")
let appInputPlan = CodexHandoffPlanner.plan(for: "Obsidianに入力して", recentMessages: [])
expect(appInputPlan?.category == .computerUse, "GUI input requests should be computer-use handoffs")

print("PASS: TypingWithMyPetsCore smoke tests")
