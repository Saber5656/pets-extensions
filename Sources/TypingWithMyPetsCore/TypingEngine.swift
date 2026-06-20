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
        let nextInput = String(Array(rawInput).prefix(target.count))
        let previous = Array(input)
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
        } else if next.count == previous.count, next != previous {
            event = .correct
            for index in 0..<next.count where next[index] != previous[index] {
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
        )
    ]
}
