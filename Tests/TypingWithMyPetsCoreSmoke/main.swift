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

print("PASS: TypingWithMyPetsCore smoke tests")
