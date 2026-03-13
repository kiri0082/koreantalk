import SwiftUI

struct MessageBubble: View {

    let message: ChatMessage
    let isSpeaking: Bool
    var onReplaySpeech: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 56)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.content.isEmpty ? " " : message.content)
                    .font(.body)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.blue.opacity(isSpeaking ? 0.7 : 0), lineWidth: 2)
                            .animation(
                                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                value: isSpeaking
                            )
                    )

                // Replay button for assistant messages
                if message.role == .assistant && !message.content.isEmpty && !message.isStreaming {
                    Button(action: onReplaySpeech) {
                        Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(isSpeaking ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 56)
            }
        }
        .padding(.horizontal, 12)
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:      return .blue
        case .assistant: return Color(.systemGray5)
        case .system:    return .clear
        }
    }
}
