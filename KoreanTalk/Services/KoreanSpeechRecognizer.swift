import Speech
import AVFoundation
import os

@MainActor
final class KoreanSpeechRecognizer: ObservableObject {

    @Published var recognizedText = ""
    @Published var isListening = false
    @Published var speechPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var micPermission = false

    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    var silenceThreshold: TimeInterval = 2.5

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscript = ""

    init() {
        speechPermission = SFSpeechRecognizer.authorizationStatus()
        Logger.stt.info("KoreanSpeechRecognizer init — ko-KR recognizer available: \(SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))?.isAvailable ?? false)")
        Logger.stt.info("Initial speech permission: \(self.speechPermission.rawValue)")
    }

    var hasPermissions: Bool {
        speechPermission == .authorized && micPermission
    }

    func requestPermissions() async {
        Logger.stt.info("Requesting speech + microphone permissions…")

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechPermission = speechStatus
        Logger.stt.info("Speech permission result: \(speechStatus.rawValue) (\(self.permissionLabel(speechStatus)))")

        micPermission = await AVAudioApplication.requestRecordPermission()
        Logger.stt.info("Microphone permission result: \(self.micPermission)")

        if !hasPermissions {
            Logger.stt.error("Missing permissions — speech:\(speechStatus.rawValue) mic:\(self.micPermission). App cannot listen without both.")
        }
    }

    func startListening() throws {
        guard !isListening else {
            Logger.stt.warning("startListening called but already listening — ignoring")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            Logger.stt.error("Korean recognizer unavailable (recognizer=\(self.recognizer == nil ? "nil" : "exists"), available=\(self.recognizer?.isAvailable ?? false))")
            throw RecognizerError.recognizerUnavailable
        }

        Logger.stt.info("Starting STT — silence threshold: \(self.silenceThreshold)s")

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            Logger.audio.info("Audio session activated for STT")
        } catch {
            Logger.audio.error("Audio session setup failed: \(error.localizedDescription)")
            throw error
        }

        recognizedText = ""
        lastTranscript = ""
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Logger.audio.info("Input format: \(format.sampleRate)Hz, channels=\(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        Logger.stt.info("Audio engine started ✓")

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    let transcript = result.bestTranscription.formattedString

                    if transcript != self.lastTranscript {
                        self.lastTranscript = transcript
                        self.recognizedText = transcript
                        Logger.stt.debug("Partial: \"\(transcript)\"")
                        self.resetSilenceTimer()
                    }

                    if result.isFinal {
                        Logger.stt.info("Final result: \"\(transcript)\"")
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = nil
                        self.commit(text: transcript)
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                // 1110 = no speech detected, 216 = task cancelled — both expected, not real errors
                if nsError.code == 1110 || nsError.code == 216 {
                    Logger.stt.debug("STT ended with expected code \(nsError.code) — ignoring")
                } else {
                    Logger.stt.error("STT error code=\(nsError.code): \(error.localizedDescription)")
                    Task { @MainActor in
                        self.tearDown()
                        self.onError?(error)
                    }
                }
            }
        }

        isListening = true
        resetSilenceTimer()
    }

    func stopAndFinalize() {
        Logger.stt.info("stopAndFinalize called — current text: \"\(self.recognizedText)\"")
        let text = recognizedText
        tearDown()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onFinalResult?(trimmed)
        }
    }

    func cancel() {
        Logger.stt.info("STT cancelled")
        tearDown()
    }

    // MARK: - Private

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                let text = self.recognizedText
                Logger.stt.info("Silence timer fired — finalizing with: \"\(text)\"")
                self.tearDown()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.onFinalResult?(trimmed)
                } else {
                    Logger.stt.info("Silence timer fired with no speech — notifying empty")
                    self.onFinalResult?("")
                }
            }
        }
    }

    private func commit(text: String) {
        tearDown()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onFinalResult?(trimmed)
        }
    }

    private func tearDown() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        recognizedText = ""
        lastTranscript = ""

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            Logger.audio.info("Audio session deactivated")
        } catch {
            Logger.audio.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    private func permissionLabel(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    enum RecognizerError: LocalizedError {
        case recognizerUnavailable

        var errorDescription: String? {
            "Korean speech recognizer is not available on this device."
        }
    }
}
