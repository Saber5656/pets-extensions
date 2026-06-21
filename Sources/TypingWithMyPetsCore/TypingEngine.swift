import Foundation

public struct Exercise: Equatable, Sendable {
    public let id: String
    public let title: String
    public let text: String

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

public enum TypingEvent: Equatable, Sendable {
    case start
    case idle
    case correct
    case error
    case delete
    case complete
}

public struct TypingMetrics: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let typedCharacters: Int
    public let liveErrors: Int
    public let totalTyped: Int
    public let totalErrors: Int
    public let progress: Double
    public let wpm: Double
    public let accuracy: Double
    public let completed: Bool
}

public struct CharacterFeedback: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case correct
        case incorrect
        case current
        case pending
    }

    public let character: Character
    public let state: State
}

public struct TypingSession: Equatable, Sendable {
    public let exercise: Exercise
    public private(set) var input: String
    public private(set) var startedAt: TimeInterval
    public private(set) var lastInputAt: TimeInterval
    public private(set) var completedAt: TimeInterval?
    public private(set) var totalTyped: Int
    public private(set) var totalErrors: Int
    public private(set) var correctStreak: Int
    public private(set) var lastEvent: TypingEvent

    public init(exercise: Exercise, now: TimeInterval = Date().timeIntervalSince1970) {
        self.exercise = exercise
        self.input = ""
        self.startedAt = now
        self.lastInputAt = now
        self.completedAt = nil
        self.totalTyped = 0
        self.totalErrors = 0
        self.correctStreak = 0
        self.lastEvent = .start
    }

    public var metrics: TypingMetrics {
        metrics(at: completedAt ?? Date().timeIntervalSince1970)
    }

    @discardableResult
    public mutating func update(rawInput: String, now: TimeInterval = Date().timeIntervalSince1970) -> TypingEvent {
        let target = Array(exercise.text)
        let proposedInput = String(Array(rawInput).prefix(target.count))
        let previousInput = input
        let previous = Array(previousInput)
        let acceptsAppend = proposedInput.hasPrefix(previousInput)
        let acceptsDelete = previousInput.hasPrefix(proposedInput)
        let nextInput = acceptsAppend || acceptsDelete ? proposedInput : previousInput
        let next = Array(nextInput)
        var event: TypingEvent = .idle

        if next.count > previous.count {
            event = .correct
            for index in previous.count..<next.count {
                totalTyped += 1
                if index < target.count, next[index] == target[index] {
                    correctStreak += 1
                } else {
                    totalErrors += 1
                    correctStreak = 0
                    event = .error
                }
            }
        } else if next.count < previous.count {
            event = .delete
            if liveErrorCount(target: target, input: next) > 0 {
                correctStreak = 0
            } else {
                correctStreak = min(correctStreak, next.count)
            }
        }

        input = nextInput
        lastInputAt = now

        if input == exercise.text {
            completedAt = completedAt ?? now
            event = .complete
        } else {
            completedAt = nil
        }

        lastEvent = event
        return event
    }

    public func metrics(at now: TimeInterval) -> TypingMetrics {
        let target = Array(exercise.text)
        let current = Array(input)
        let elapsed = max(0, now - startedAt)
        let elapsedMinutes = elapsed / 60
        let progress = target.isEmpty ? 1 : Double(current.count) / Double(target.count)
        let wpm = elapsedMinutes > 0 ? Double(current.count) / 5 / elapsedMinutes : 0
        let accuracy = totalTyped > 0
            ? max(0, Double(totalTyped - totalErrors) / Double(totalTyped) * 100)
            : 100

        return TypingMetrics(
            elapsed: elapsed,
            typedCharacters: current.count,
            liveErrors: liveErrorCount(target: target, input: current),
            totalTyped: totalTyped,
            totalErrors: totalErrors,
            progress: progress,
            wpm: wpm,
            accuracy: accuracy,
            completed: input == exercise.text
        )
    }
}

public func feedback(for target: String, input: String) -> [CharacterFeedback] {
    let targetCharacters = Array(target)
    let inputCharacters = Array(input)

    return targetCharacters.enumerated().map { index, character in
        if index >= inputCharacters.count {
            return CharacterFeedback(
                character: character,
                state: index == inputCharacters.count ? .current : .pending
            )
        }

        return CharacterFeedback(
            character: character,
            state: inputCharacters[index] == character ? .correct : .incorrect
        )
    }
}

public func liveErrorCount(target: [Character], input: [Character]) -> Int {
    var errors = 0
    for index in 0..<input.count {
        if index >= target.count || input[index] != target[index] {
            errors += 1
        }
    }
    return errors
}

public func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded(.down)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

public func typingScore(for metrics: TypingMetrics) -> Int {
    let progressScore = metrics.progress * 500.0
    let speedScore = min(metrics.wpm, 120.0) * 5.0
    let accuracyWeight = metrics.typedCharacters > 0 ? metrics.progress : 0.0
    let accuracyScore = metrics.accuracy * 4.0 * accuracyWeight
    let completionBonus = metrics.completed ? 250.0 : 0.0
    let errorPenalty = Double(max(metrics.totalErrors, metrics.liveErrors)) * 35.0
    let rawScore = progressScore + speedScore + accuracyScore + completionBonus - errorPenalty

    return max(0, Int(rawScore.rounded()))
}

public extension Exercise {
    static let defaults: [Exercise] = [
        Exercise(
            id: "steady-steps",
            title: "Steady Steps",
            text: "Small steady steps make a sharp mind feel lighter."
        ),
        Exercise(
            id: "tiny-review",
            title: "Tiny Review",
            text: "Read the code, name the risk, make the smallest useful change."
        ),
        Exercise(
            id: "japanese-focus",
            title: "Focus",
            text: "焦らずに、いま見えている一文字だけを打つ。"
        ),
        Exercise(
            id: "swift-snippet",
            title: "Swift",
            text: "let score = max(0, typed - errors)"
        ),
        Exercise(
            id: "calm-debug",
            title: "Debug",
            text: "Pause, read the log, then change one thing."
        ),
        Exercise(
            id: "clear-commit",
            title: "Commit",
            text: "Small commits make future reviews easier."
        ),
        Exercise(
            id: "focus-window",
            title: "Focus",
            text: "Keep the window small and the goal clear."
        ),
        Exercise(
            id: "steady-breath",
            title: "Steady",
            text: "A steady breath makes careful typing easier."
        ),
        Exercise(
            id: "ship-safely",
            title: "Ship",
            text: "Ship the fix after the check turns green."
        ),
        Exercise(
            id: "tiny-loop",
            title: "Loop",
            text: "Try, observe, adjust, and try again."
        ),
        Exercise(
            id: "bright-terminal",
            title: "Terminal",
            text: "The terminal tells a story if you read it."
        ),
        Exercise(
            id: "kind-review",
            title: "Review",
            text: "A kind review still names the real risk."
        ),
        Exercise(
            id: "local-first",
            title: "Local",
            text: "Prefer local checks before remote surprises."
        ),
        Exercise(
            id: "sharp-diff",
            title: "Diff",
            text: "A sharp diff explains the shape of the work."
        ),
        Exercise(
            id: "gentle-speed",
            title: "Speed",
            text: "Speed grows from rhythm, not from panic."
        ),
        Exercise(
            id: "error-signal",
            title: "Signal",
            text: "Every error is a signal with a location."
        ),
        Exercise(
            id: "quiet-state",
            title: "State",
            text: "Name the state before changing the view."
        ),
        Exercise(
            id: "short-path",
            title: "Path",
            text: "Take the short path only after you see it."
        ),
        Exercise(
            id: "clean-prompt",
            title: "Prompt",
            text: "Clean prompts make clean answers more likely."
        ),
        Exercise(
            id: "mouse-free",
            title: "Keys",
            text: "Hands on keys, eyes on the next character."
        ),
        Exercise(
            id: "日本語-観察",
            title: "観察",
            text: "まず観察してから、短い変更を入れる。"
        ),
        Exercise(
            id: "日本語-集中",
            title: "集中",
            text: "一文ずつ、焦らず、正確に打つ。"
        ),
        Exercise(
            id: "日本語-確認",
            title: "確認",
            text: "動いた理由と、残る不安を分けて書く。"
        ),
        Exercise(
            id: "日本語-余白",
            title: "余白",
            text: "少し余白があると、判断も読みやすい。"
        )
    ]
}
