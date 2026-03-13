import Foundation
import os

enum UserIntent {
    case help
    case continueConversation
    case setDifficulty(DifficultyLevel)
    case adjustSpeed(SpeedAdjustment)
    case normalInput

    enum SpeedAdjustment {
        case slower, faster
    }
}

final class IntentDetector {

    func detect(in text: String, currentDifficulty: DifficultyLevel) -> UserIntent {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let result = classify(lower, currentDifficulty: currentDifficulty)
        Logger.intent.info("Input: \"\(text)\" → \(self.intentLabel(result))")
        return result
    }

    private func classify(_ lower: String, currentDifficulty: DifficultyLevel) -> UserIntent {
        if matchesAny(lower, patterns: [
            "help", "헬프", "헬",
            "도움말", "도움", "뭐라고", "무슨 말", "모르겠", "이해 못",
            "what did you say", "i don't understand", "i didn't understand", "explain"
        ]) { return .help }

        if matchesAny(lower, patterns: [
            "continue", "컨티뉴", "계속", "고 온", "고온",
            "go on", "go ahead", "resume", "keep going", "let's continue", "ok continue"
        ]) { return .continueConversation }

        if matchesAny(lower, patterns: ["beginner", "easy mode", "초급", "start over easy"]) {
            return .setDifficulty(.beginner)
        }
        if matchesAny(lower, patterns: ["intermediate", "medium level", "중급"]) {
            return .setDifficulty(.intermediate)
        }
        if matchesAny(lower, patterns: ["advanced", "expert", "고급", "native level"]) {
            return .setDifficulty(.advanced)
        }

        if matchesAny(lower, patterns: [
            "harder", "more difficult", "make it harder", "level up",
            "더 어렵게", "too easy", "challenge me"
        ]) { return .setDifficulty(currentDifficulty.stepped(up: true)) }

        if matchesAny(lower, patterns: [
            "easier", "make it easier", "too difficult", "too hard",
            "level down", "더 쉽게", "slow it down", "simplify"
        ]) { return .setDifficulty(currentDifficulty.stepped(up: false)) }

        if matchesAny(lower, patterns: [
            "slower", "slow down", "speak slower", "speak more slowly",
            "too fast", "천천히", "느리게", "더 천천히"
        ]) { return .adjustSpeed(.slower) }

        if matchesAny(lower, patterns: [
            "faster", "speed up", "speak faster", "빨리", "빠르게", "더 빠르게"
        ]) { return .adjustSpeed(.faster) }

        return .normalInput
    }

    private func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private func intentLabel(_ intent: UserIntent) -> String {
        switch intent {
        case .help:                        return "help"
        case .continueConversation:        return "continue"
        case .setDifficulty(let l):        return "setDifficulty(\(l.rawValue))"
        case .adjustSpeed(.slower):        return "adjustSpeed(slower)"
        case .adjustSpeed(.faster):        return "adjustSpeed(faster)"
        case .normalInput:                 return "normalInput"
        }
    }
}
