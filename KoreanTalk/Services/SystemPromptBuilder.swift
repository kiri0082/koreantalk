import Foundation

final class SystemPromptBuilder {

    func buildConversationPrompt(difficulty: DifficultyLevel) -> String {
        """
        You are a Korean conversation partner helping the user practice spoken Korean.
        Respond in Korean only (Hangul, no romanization). Keep replies to 1-3 sentences and always end with a question.
        Gently correct mistakes by showing the correct form once, then continue.
        If the user says "help", explain your last message in English and end with: Say 'continue' when you're ready.
        Difficulty: \(difficulty.rawValue) — \(difficultyInstructions(difficulty))
        """
    }

    private func difficultyInstructions(_ difficulty: DifficultyLevel) -> String {
        switch difficulty {
        case .beginner:
            return "basic vocabulary, short simple sentences, 해요체 only, present tense."
        case .intermediate:
            return "varied vocabulary, mixed tenses, connective endings (-서, -니까, -는데), 해요체 and 합쇼체."
        case .advanced:
            return "native-level speech, full honorifics (반말/존댓말), idioms, proverbs (속담), nuanced corrections."
        }
    }
}
