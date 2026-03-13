import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {

    var settings: AppSettings
    @Published var isTesting = false
    @Published var connectionResult: Bool? = nil

    private let aiClient: OpenAICompatibleClient
    private let ttsService: KoreanTTSService
    private var cancellables = Set<AnyCancellable>()

    var elevenLabsVoices: [KoreanTTSService.ElevenLabsVoice] { ttsService.availableVoices }

    init(settings: AppSettings, aiClient: OpenAICompatibleClient, ttsService: KoreanTTSService) {
        self.settings = settings
        self.aiClient = aiClient
        self.ttsService = ttsService

        // Forward voice list changes so the picker re-renders
        ttsService.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func testConnection() async {
        isTesting = true
        connectionResult = nil

        aiClient.updateConfig(.init(
            baseURL: settings.apiBaseURL,
            apiKey: settings.apiKey,
            model: settings.modelName
        ))

        connectionResult = await aiClient.isReachable()
        isTesting = false

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            connectionResult = nil
        }
    }

    func previewVoice() {
        ttsService.speak("안녕하세요! 잘 지내셨어요?", rate: settings.ttsRate, messageId: UUID())
    }
}
