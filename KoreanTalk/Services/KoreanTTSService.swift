import AVFoundation
import os

@MainActor
final class KoreanTTSService: NSObject, ObservableObject {

    @Published var isSpeaking = false
    @Published var speakingMessageId: UUID?

    var onSpeakingFinished: (() -> Void)?
    var onCloudTTSError: ((String) -> Void)?

    private var googleAPIKey: String = ""
    private var audioPlayer: AVAudioPlayer?

    // Device TTS fallback
    private let synthesizer = AVSpeechSynthesizer()
    private var koreanVoice: AVSpeechSynthesisVoice?
    private var englishVoice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        synthesizer.delegate = self
        selectBestKoreanVoice()
        selectBestEnglishVoice()
        warmUpAudioSession()
    }

    func updateGoogleAPIKey(_ key: String) {
        googleAPIKey = key
        cachedVoiceID = nil
        Logger.tts.info("ElevenLabs key updated — cloud TTS \(key.isEmpty ? "disabled (device fallback)" : "enabled")")
        if !key.isEmpty {
            Task { await fetchFirstAvailableVoice() }
        }
    }

    // MARK: - Public interface

    func speak(_ text: String, rate: Float, messageId: UUID, isEnglish: Bool = false) {
        stop()
        configureAudioSession()
        speakingMessageId = messageId
        isSpeaking = true

        let preview = String(text.prefix(60))
        let engine = googleAPIKey.isEmpty ? "device" : "cloud"
        Logger.tts.info("Speaking via \(engine) [\(preview)…] rate=\(rate) english=\(isEnglish)")

        if googleAPIKey.isEmpty {
            speakViaDevice(text: text, rate: rate, isEnglish: isEnglish)
        } else {
            Task { await speakViaCloud(text: text, rate: rate, isEnglish: isEnglish) }
        }
    }

    func stop() {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
            audioPlayer = nil
        }
        if synthesizer.isSpeaking {
            Logger.tts.info("TTS stopped by caller")
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakingMessageId = nil
    }

    // MARK: - Cloud TTS (ElevenLabs)

    struct ElevenLabsVoice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    @Published var availableVoices: [ElevenLabsVoice] = []
    var preferredVoiceID: String = ""

    private var cachedVoiceID: String? = nil

    func selectVoice(id: String) {
        preferredVoiceID = id
        cachedVoiceID = id.isEmpty ? availableVoices.first?.id : id
        Logger.tts.info("Voice selected: \(id.isEmpty ? "(auto)" : id)")
    }

    private func fetchFirstAvailableVoice() async {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return }
        var request = URLRequest(url: url)
        request.setValue(googleAPIKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Logger.tts.info("ElevenLabs /v1/voices → HTTP \(status)")

            if status != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                Logger.tts.error("ElevenLabs voices error: \(body)")
                onCloudTTSError?(friendlyTTSError(TTSError.httpError(status)))
                return
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let voices = json["voices"] as? [[String: Any]]
            else {
                Logger.tts.error("Failed to parse ElevenLabs voices response: \(String(data: data, encoding: .utf8) ?? "")")
                return
            }
            availableVoices = voices.compactMap { v -> ElevenLabsVoice? in
                guard let id = v["voice_id"] as? String, let name = v["name"] as? String else { return nil }
                return ElevenLabsVoice(id: id, name: name)
            }
            if let preferred = availableVoices.first(where: { $0.id == preferredVoiceID }), !preferredVoiceID.isEmpty {
                cachedVoiceID = preferred.id
                Logger.tts.info("ElevenLabs voice (preferred): \(preferred.name) (\(preferred.id))")
            } else if let first = availableVoices.first {
                cachedVoiceID = first.id
                Logger.tts.info("ElevenLabs voice (auto): \(first.name) (\(first.id))")
            }
        } catch {
            Logger.tts.error("Failed to fetch ElevenLabs voices: \(error.localizedDescription)")
        }
    }

    private func speakViaCloud(text: String, rate: Float, isEnglish: Bool) async {
        if cachedVoiceID == nil { await fetchFirstAvailableVoice() }
        do {
            let data = try await fetchElevenLabsAudio(text: text, rate: rate, isEnglish: isEnglish)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            player.play()
        } catch {
            let message = friendlyTTSError(error)
            Logger.tts.error("Cloud TTS failed: \(error.localizedDescription) — falling back to device")
            onCloudTTSError?(message)
            speakViaDevice(text: text, rate: rate, isEnglish: isEnglish)
        }
    }

    private func fetchElevenLabsAudio(text: String, rate: Float, isEnglish: Bool) async throws -> Data {
        guard let voiceID = cachedVoiceID else { throw TTSError.noVoiceAvailable }
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"
        guard let url = URL(string: urlString) else { throw TTSError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleAPIKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15

        // Map AVSpeechSynthesizer rate (0.20–0.65) → ElevenLabs speed (0.7–1.2)
        let normalized = Double(rate - 0.20) / Double(0.65 - 0.20)
        let elevenLabsSpeed = max(0.7, min(1.2, 0.7 + normalized * 0.5))
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "speed": elevenLabsSpeed
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            Logger.tts.error("ElevenLabs TTS HTTP \(http.statusCode): \(msg)")
            throw TTSError.httpError(http.statusCode)
        }

        return data  // ElevenLabs returns raw MP3 bytes directly
    }

    private func friendlyTTSError(_ error: Error) -> String {
        if let ttsError = error as? TTSError, case .httpError(let code) = ttsError {
            switch code {
            case 401: return "Invalid ElevenLabs key — check your key in Settings. Using device voice."
            case 422: return "ElevenLabs monthly limit reached (10k chars free). Using device voice."
            case 429: return "ElevenLabs rate limit — using device voice temporarily."
            default:  return "ElevenLabs error \(code) — using device voice."
            }
        }
        return "ElevenLabs unavailable — using device voice."
    }

    // MARK: - Device TTS fallback

    private func speakViaDevice(text: String, rate: Float, isEnglish: Bool) {
        let utterance = AVSpeechUtterance(string: text)
        if isEnglish {
            utterance.voice = englishVoice
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
        } else {
            utterance.voice = koreanVoice
            utterance.rate = rate
            utterance.pitchMultiplier = 1.1
        }
        utterance.postUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    // MARK: - Setup

    private func warmUpAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            Logger.audio.info("Audio session pre-warmed at startup")
        } catch {
            Logger.audio.error("Audio session pre-warm failed: \(error.localizedDescription)")
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.audio.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func selectBestKoreanVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ko-KR" }
        Logger.tts.info("Korean voices: \(voices.count)")
        for v in voices { Logger.tts.info("  • \(v.name) quality=\(v.quality.rawValue)") }
        koreanVoice = voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? voices.first
            ?? AVSpeechSynthesisVoice(language: "ko-KR")
        if let v = koreanVoice { Logger.tts.info("Selected Korean voice: \(v.name)") }
    }

    private func selectBestEnglishVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en-US") }
        englishVoice = voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? voices.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
        if let v = englishVoice { Logger.tts.info("Selected English voice: \(v.name)") }
    }

    // MARK: - Errors

    enum TTSError: Error {
        case invalidURL
        case httpError(Int)
        case invalidResponse
        case noVoiceAvailable
    }
}

// MARK: - AVAudioPlayerDelegate (cloud TTS completion)

extension KoreanTTSService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            Logger.tts.info("Cloud TTS finished")
            self.isSpeaking = false
            self.speakingMessageId = nil
            self.audioPlayer = nil
            self.onSpeakingFinished?()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate (device TTS completion)

extension KoreanTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            Logger.tts.info("Device TTS finished")
            self.isSpeaking = false
            self.speakingMessageId = nil
            self.onSpeakingFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            Logger.tts.info("Device TTS cancelled")
            self.isSpeaking = false
            self.speakingMessageId = nil
        }
    }
}
