import os

/// Centralised loggers — visible in Xcode Console and Console.app
/// Filter by subsystem "com.koreantalk.app" to see only KoreanTalk logs
extension Logger {
    private static let subsystem = "com.koreantalk.app"

    /// AI API requests / responses / errors
    static let api     = Logger(subsystem: subsystem, category: "API")

    /// Speech-to-text lifecycle
    static let stt     = Logger(subsystem: subsystem, category: "STT")

    /// Text-to-speech lifecycle
    static let tts     = Logger(subsystem: subsystem, category: "TTS")

    /// Conversation state machine transitions
    static let vm      = Logger(subsystem: subsystem, category: "ViewModel")

    /// Intent detection results
    static let intent  = Logger(subsystem: subsystem, category: "Intent")

    /// Audio session configuration
    static let audio   = Logger(subsystem: subsystem, category: "Audio")

    /// App startup / settings
    static let app     = Logger(subsystem: subsystem, category: "App")
}
