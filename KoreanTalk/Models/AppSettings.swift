import Foundation
import Combine

final class AppSettings: ObservableObject {

    private let defaults = UserDefaults.standard

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published var apiBaseURL: String {
        didSet { defaults.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: Keys.modelName) }
    }
    @Published var ttsRate: Float {
        didSet { defaults.set(ttsRate, forKey: Keys.ttsRate) }
    }
    @Published var difficultyLevel: DifficultyLevel {
        didSet { defaults.set(difficultyLevel.rawValue, forKey: Keys.difficultyLevel) }
    }

    @Published var autoListenEnabled: Bool {
        didSet { defaults.set(autoListenEnabled, forKey: Keys.autoListen) }
    }
    @Published var elevenLabsKey: String {
        didSet { defaults.set(elevenLabsKey, forKey: Keys.elevenLabsKey) }
    }
    @Published var elevenLabsVoiceID: String {
        didSet { defaults.set(elevenLabsVoiceID, forKey: Keys.elevenLabsVoiceID) }
    }

    init() {
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        apiBaseURL = defaults.string(forKey: Keys.apiBaseURL)
            ?? "https://api.groq.com/openai/v1"
        modelName = defaults.string(forKey: Keys.modelName) ?? "llama-3.3-70b-versatile"
        let savedRate = defaults.float(forKey: Keys.ttsRate)
        ttsRate = savedRate > 0 ? savedRate : 0.42
        let savedDifficulty = defaults.string(forKey: Keys.difficultyLevel) ?? ""
        difficultyLevel = DifficultyLevel(rawValue: savedDifficulty) ?? .beginner
        // Auto-listen on by default — hands-free is the primary use case
        autoListenEnabled = defaults.object(forKey: Keys.autoListen) as? Bool ?? true
        elevenLabsKey = defaults.string(forKey: Keys.elevenLabsKey) ?? ""
        elevenLabsVoiceID = defaults.string(forKey: Keys.elevenLabsVoiceID) ?? ""
    }

    private enum Keys {
        static let apiKey = "kt.apiKey"
        static let apiBaseURL = "kt.apiBaseURL"
        static let modelName = "kt.modelName"
        static let ttsRate = "kt.ttsRate"
        static let difficultyLevel = "kt.difficultyLevel"
        static let autoListen = "kt.autoListen"
        static let elevenLabsKey = "kt.elevenLabsKey"
        static let elevenLabsVoiceID = "kt.elevenLabsVoiceID"
    }
}
