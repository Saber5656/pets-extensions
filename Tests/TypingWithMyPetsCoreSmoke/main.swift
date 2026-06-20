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

_ = session.update(rawInput: "ax", now: 31)
_ = session.update(rawInput: "a", now: 32)
expect(session.metrics(at: 32).totalErrors == 1, "deleted mistakes remain counted")

let states = feedback(for: "abcd", input: "ax").map(\.state)
expect(states == [.correct, .incorrect, .current, .pending], "feedback states should match")

print("PASS: TypingWithMyPetsCore smoke tests")
