import SwiftUI

struct MicButton: View {

    let state: ConversationState
    var onPress: () -> Void
    var onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Pulse ring while listening
            if case .listening = state {
                Circle()
                    .stroke(Color.red.opacity(0.25), lineWidth: 4)
                    .frame(width: 96, height: 96)
                    .scaleEffect(isPressed ? 1.18 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: isPressed
                    )
            }

            Circle()
                .fill(buttonColor)
                .frame(width: 72, height: 72)
                .shadow(color: buttonColor.opacity(0.35), radius: 8, y: 4)

            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: {
                    if case .speaking = state { return true }
                    return false
                }())
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onPress()
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
        .disabled(!state.allowsMicPress)
        .opacity(state.allowsMicPress ? 1.0 : 0.45)
    }

    private var buttonColor: Color {
        switch state {
        case .idle, .helpPaused: return .blue
        case .listening:          return .red
        case .processing:         return .orange
        case .speaking:           return .green
        case .error:              return .gray
        }
    }

    private var iconName: String {
        switch state {
        case .idle, .helpPaused: return "mic.fill"
        case .listening:          return "waveform"
        case .processing:         return "ellipsis"
        case .speaking:           return "speaker.wave.2.fill"
        case .error:              return "exclamationmark.triangle.fill"
        }
    }
}
