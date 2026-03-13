import Foundation
import Combine
import os

enum ConversationState {
    case idle
    case listening
    case processing
    case speaking
    case helpPaused
    case error(String)

    var allowsMicPress: Bool {
        switch self {
        case .idle, .helpPaused: return true
        default: return false
        }
    }

    var isListeningOrIdle: Bool {
        switch self {
        case .idle, .listening: return true
        default: return false
        }
    }

    var debugDescription: String {
        switch self {
        case .idle:            return "idle"
        case .listening:       return "listening"
        case .processing:      return "processing"
        case .speaking:        return "speaking"
        case .helpPaused:      return "helpPaused"
        case .error(let msg):  return "error(\(msg))"
        }
    }
}

@MainActor
final class ConversationViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var conversationState: ConversationState = .idle {
        didSet { Logger.vm.info("State: \(oldValue.debugDescription) → \(self.conversationState.debugDescription)") }
    }
    @Published var difficultyFeedback: DifficultyLevel? = nil
    @Published var speedFeedback: String? = nil
    @Published var liveTranscript: String = ""
    @Published var errorBanner: String? = nil

    let settings: AppSettings
    let ttsService: KoreanTTSService
    let speechRecognizer: KoreanSpeechRecognizer
    private let aiClient: OpenAICompatibleClient
    private let promptBuilder: SystemPromptBuilder
    private let intentDetector: IntentDetector

    private var streamTask: Task<Void, Never>?
    private var isInHelpMode = false
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings,
        aiClient: OpenAICompatibleClient,
        ttsService: KoreanTTSService,
        speechRecognizer: KoreanSpeechRecognizer,
        promptBuilder: SystemPromptBuilder,
        intentDetector: IntentDetector
    ) {
        self.settings = settings
        self.aiClient = aiClient
        self.ttsService = ttsService
        self.speechRecognizer = speechRecognizer
        self.promptBuilder = promptBuilder
        self.intentDetector = intentDetector

        Logger.vm.info("ConversationViewModel init — difficulty=\(settings.difficultyLevel.rawValue), autoListen=\(settings.autoListenEnabled)")
        setupCallbacks()

        speechRecognizer.$recognizedText
            .receive(on: RunLoop.main)
            .assign(to: &$liveTranscript)

        Task { await openingGreeting() }
    }

    private func setupCallbacks() {
        speechRecognizer.onFinalResult = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveTranscript = ""

                if text.isEmpty {
                    Logger.vm.info("STT returned empty (silence) — autoListen=\(self.settings.autoListenEnabled)")
                    self.conversationState = .idle
                    if self.settings.autoListenEnabled && !self.isInHelpMode {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        self.startListening()
                    }
                    return
                }

                Logger.vm.info("STT final: \"\(text)\"")
                await self.processUserInput(text)
            }
        }
        speechRecognizer.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                Logger.vm.error("STT error received in VM: \(error.localizedDescription)")
                self?.conversationState = .idle
            }
        }
        ttsService.onSpeakingFinished = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onSpeakingFinished()
            }
        }
        ttsService.onCloudTTSError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.showError(message)
            }
        }
    }

    func startNewConversation() {
        Logger.vm.info("Starting new conversation")
        streamTask?.cancel()
        ttsService.stop()
        speechRecognizer.cancel()
        messages = []
        isInHelpMode = false
        conversationState = .idle
        liveTranscript = ""
        Task { await openingGreeting() }
    }

    private func openingGreeting() async {
        Logger.vm.info("Sending opening greeting (difficulty=\(self.settings.difficultyLevel.rawValue))")
        let apiMessages: [APIMessage] = [
            APIMessage(role: "system", content: promptBuilder.buildConversationPrompt(difficulty: settings.difficultyLevel)),
            APIMessage(role: "user", content: "안녕하세요! 한국어 대화 연습을 시작해 주세요.")
        ]
        await streamAIResponse(apiMessages: apiMessages)
    }

    func startListening() {
        guard conversationState.allowsMicPress else {
            Logger.vm.warning("startListening blocked — state is \(self.conversationState.debugDescription)")
            return
        }
        guard speechRecognizer.hasPermissions else {
            Logger.vm.error("startListening blocked — missing permissions (speech=\(self.speechRecognizer.speechPermission.rawValue), mic=\(self.speechRecognizer.micPermission))")
            return
        }

        ttsService.stop()

        do {
            try speechRecognizer.startListening()
            conversationState = .listening
        } catch {
            Logger.vm.error("startListening threw: \(error.localizedDescription)")
            conversationState = .error(error.localizedDescription)
        }
    }

    func stopListeningAndSend() {
        guard case .listening = conversationState else { return }
        conversationState = .processing
        speechRecognizer.stopAndFinalize()
    }

    func cancelListening() {
        Logger.vm.info("cancelListening called")
        speechRecognizer.cancel()
        liveTranscript = ""
        conversationState = .idle
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Logger.vm.info("sendText: \"\(trimmed)\"")
        Task { await processUserInput(trimmed) }
    }

    private func processUserInput(_ text: String) async {
        let intent = intentDetector.detect(in: text, currentDifficulty: settings.difficultyLevel)
        switch intent {
        case .help:                        await handleHelp(userText: text)
        case .continueConversation:        await handleContinue(userText: text)
        case .setDifficulty(let level):    await handleDifficultyChange(to: level, userText: text)
        case .adjustSpeed(let adj):        await handleSpeedChange(adj, userText: text)
        case .normalInput:                 await handleNormalInput(text)
        }
    }

    private func handleHelp(userText: String) async {
        Logger.vm.info("HELP requested — entering help mode")
        isInHelpMode = true
        addUserMessage(userText)
        let instruction = """
            The user said "help". Explain in plain English what your last message meant.
            Be clear and concise. End with exactly: "Say 'continue' when you're ready to go on."
            Respond in English only for this message.
            """
        await streamAIResponse(apiMessages: buildAPIMessages(overrideInstruction: instruction))
    }

    private func handleContinue(userText: String) async {
        Logger.vm.info("CONTINUE — exiting help mode, resuming Korean")
        isInHelpMode = false
        addUserMessage(userText)
        let instruction = """
            The user said "continue". Resume the Korean conversation naturally from where you left off.
            Respond in Korean only.
            """
        await streamAIResponse(apiMessages: buildAPIMessages(overrideInstruction: instruction))
    }

    private func handleDifficultyChange(to level: DifficultyLevel, userText: String) async {
        Logger.vm.info("Difficulty changed: \(self.settings.difficultyLevel.rawValue) → \(level.rawValue)")
        settings.difficultyLevel = level
        settings.ttsRate = level.defaultTTSRate
        difficultyFeedback = level
        addUserMessage(userText)

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            difficultyFeedback = nil
        }

        let instruction = """
            The user has changed the difficulty to \(level.rawValue).
            Acknowledge this briefly in Korean (one short sentence), then ask a follow-up question at the \(level.rawValue) level.
            Apply the \(level.rawValue) difficulty rules immediately from this response forward.
            """
        await streamAIResponse(apiMessages: buildAPIMessages(overrideInstruction: instruction))
    }

    private func handleSpeedChange(_ adjustment: UserIntent.SpeedAdjustment, userText: String) async {
        let step: Float = 0.08
        let oldRate = settings.ttsRate
        switch adjustment {
        case .slower:
            settings.ttsRate = max(0.20, settings.ttsRate - step)
            speedFeedback = "Slower"
        case .faster:
            settings.ttsRate = min(0.65, settings.ttsRate + step)
            speedFeedback = "Faster"
        }
        Logger.vm.info("Speed changed: \(oldRate) → \(self.settings.ttsRate)")
        addUserMessage(userText)

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            speedFeedback = nil
        }

        let direction = adjustment == .slower ? "더 천천히" : "더 빠르게"
        let instruction = """
            The user asked you to speak \(adjustment == .slower ? "more slowly" : "faster").
            Acknowledge with one brief Korean sentence (e.g., "\(direction) 말할게요!"), then continue the conversation.
            """
        await streamAIResponse(apiMessages: buildAPIMessages(overrideInstruction: instruction))
    }

    private func handleNormalInput(_ text: String) async {
        addUserMessage(text)
        await streamAIResponse(apiMessages: buildAPIMessages())
    }

    private func streamAIResponse(apiMessages: [APIMessage]) async {
        streamTask?.cancel()
        conversationState = .processing

        Logger.vm.info("Streaming AI response — \(apiMessages.count) messages in context")

        let placeholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        let msgId = placeholder.id

        let task = Task {
            do {
                var fullText = ""

                for try await chunk in aiClient.streamChat(messages: apiMessages) {
                    if Task.isCancelled { break }
                    fullText += chunk
                    updateMessage(id: msgId, content: fullText, isStreaming: true)
                }

                Logger.vm.info("AI response complete — \(fullText.count) chars")
                updateMessage(id: msgId, content: fullText, isStreaming: false)
                speakIfNeeded(fullText, id: msgId)
            } catch {
                let msg = error.localizedDescription
                Logger.vm.error("streamAIResponse error: \(msg)")
                messages.removeAll { $0.id == msgId }  // remove empty placeholder
                showError(msg)
                conversationState = .idle
            }
        }

        streamTask = task
        await task.value
    }

    private func speakIfNeeded(_ text: String, id: UUID) {
        guard !text.isEmpty else {
            conversationState = .idle
            return
        }
        conversationState = .speaking
        ttsService.speak(text, rate: settings.ttsRate, messageId: id, isEnglish: isInHelpMode)
    }

    private func onSpeakingFinished() {
        guard case .speaking = conversationState else {
            Logger.vm.warning("onSpeakingFinished called but state is \(self.conversationState.debugDescription) — ignoring")
            return
        }

        if isInHelpMode {
            Logger.vm.info("Speaking finished — help mode, waiting for 'continue'")
            conversationState = .helpPaused
            if settings.autoListenEnabled {
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    startListening()
                }
            }
        } else if settings.autoListenEnabled {
            Logger.vm.info("Speaking finished — auto-listen enabled, restarting mic after 0.5s")
            conversationState = .idle
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                startListening()
            }
        } else {
            Logger.vm.info("Speaking finished — returning to idle")
            conversationState = .idle
        }
    }

    private func addUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, content: text))
    }

    private func updateMessage(id: UUID, content: String, isStreaming: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].isStreaming = isStreaming
    }

    func showError(_ message: String) {
        errorBanner = message
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if errorBanner == message { errorBanner = nil }
        }
    }

    private func buildAPIMessages(overrideInstruction: String? = nil) -> [APIMessage] {
        var apiMessages: [APIMessage] = [
            APIMessage(role: "system", content: promptBuilder.buildConversationPrompt(difficulty: settings.difficultyLevel))
        ]

        if let instruction = overrideInstruction {
            apiMessages.append(APIMessage(role: "system", content: instruction))
        }

        let history = messages
            .filter { !$0.isStreaming && ($0.role == .user || $0.role == .assistant) }
            .suffix(20)

        for msg in history {
            apiMessages.append(APIMessage(role: msg.role.rawValue, content: msg.content))
        }

        return apiMessages
    }
}
