import Foundation
import Combine
import os

@MainActor
final class AppEnvironment: ObservableObject {

    let settings: AppSettings
    let aiClient: OpenAICompatibleClient
    let ttsService: KoreanTTSService
    let speechRecognizer: KoreanSpeechRecognizer

    let conversationViewModel: ConversationViewModel
    let settingsViewModel: SettingsViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = AppSettings()

        Logger.app.info("──────────────────────────────────────")
        Logger.app.info("KoreanTalk starting up")
        Logger.app.info("API base URL : \(settings.apiBaseURL)")
        Logger.app.info("Model        : \(settings.modelName)")
        Logger.app.info("API key set  : \(!settings.apiKey.isEmpty)")
        Logger.app.info("Difficulty   : \(settings.difficultyLevel.rawValue)")
        Logger.app.info("TTS rate     : \(settings.ttsRate)")
        Logger.app.info("Auto-listen  : \(settings.autoListenEnabled)")
        Logger.app.info("──────────────────────────────────────")

        let aiClient = OpenAICompatibleClient(config: .init(
            baseURL: settings.apiBaseURL,
            apiKey: settings.apiKey,
            model: settings.modelName
        ))
        let ttsService = KoreanTTSService()
        ttsService.preferredVoiceID = settings.elevenLabsVoiceID
        ttsService.updateGoogleAPIKey(settings.elevenLabsKey)
        let speechRecognizer = KoreanSpeechRecognizer()
        let promptBuilder = SystemPromptBuilder()
        let intentDetector = IntentDetector()

        self.settings = settings
        self.aiClient = aiClient
        self.ttsService = ttsService
        self.speechRecognizer = speechRecognizer

        self.conversationViewModel = ConversationViewModel(
            settings: settings,
            aiClient: aiClient,
            ttsService: ttsService,
            speechRecognizer: speechRecognizer,
            promptBuilder: promptBuilder,
            intentDetector: intentDetector
        )

        self.settingsViewModel = SettingsViewModel(
            settings: settings,
            aiClient: aiClient,
            ttsService: ttsService
        )

        // Keep TTS service in sync when key or voice changes in Settings
        settings.$elevenLabsKey
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak ttsService] key in ttsService?.updateGoogleAPIKey(key) }
            .store(in: &cancellables)

        settings.$elevenLabsVoiceID
            .removeDuplicates()
            .sink { [weak ttsService] id in ttsService?.selectVoice(id: id) }
            .store(in: &cancellables)
    }
}
