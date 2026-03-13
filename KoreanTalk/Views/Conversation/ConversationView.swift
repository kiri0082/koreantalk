import SwiftUI

struct ConversationView: View {

    @ObservedObject var viewModel: ConversationViewModel
    @State private var textInput = ""
    @State private var showTextInput = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            messageList

            feedbackBanners

            if let error = viewModel.errorBanner {
                errorBannerView(error)
            }

            if case .helpPaused = viewModel.conversationState {
                helpModeBanner
            }

            Divider()

            inputArea
        }
        .task {
            await viewModel.speechRecognizer.requestPermissions()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("KoreanTalk")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(viewModel.settings.difficultyLevel.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.settings.autoListenEnabled {
                        Label("Hands-free", systemImage: "hands.and.sparkles")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            Spacer()
            Button {
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                        MessageBubble(
                            message: message,
                            isSpeaking: viewModel.ttsService.speakingMessageId == message.id,
                            onReplaySpeech: {
                                viewModel.ttsService.speak(
                                    message.content,
                                    rate: viewModel.settings.ttsRate,
                                    messageId: message.id
                                )
                            }
                        )
                    }

                    if case .processing = viewModel.conversationState {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.conversationState.debugDescription) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Feedback banners

    @ViewBuilder
    private var feedbackBanners: some View {
        if let difficulty = viewModel.difficultyFeedback {
            feedbackBanner(
                text: "Difficulty → \(difficulty.displayName)",
                icon: "chart.bar.fill",
                color: .blue
            )
        }
        if let speed = viewModel.speedFeedback {
            feedbackBanner(
                text: speed == "Slower" ? "Speaking slower" : "Speaking faster",
                icon: speed == "Slower" ? "tortoise.fill" : "hare.fill",
                color: .orange
            )
        }
    }

    private func feedbackBanner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption.bold()).foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Error banner

    private func errorBannerView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button { viewModel.errorBanner = nil } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Help mode banner

    private var helpModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            Text("Help mode — say **\"continue\"** to resume in Korean")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.blue.opacity(0.07))
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 8) {
            // Live transcript shown while listening
            if case .listening = viewModel.conversationState {
                liveTranscriptView
            }

            if showTextInput {
                HStack(spacing: 8) {
                    TextField("Type in Korean...", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { submitText() }
                    Button("Send", action: submitText)
                        .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            HStack {
                // Keyboard toggle
                Button {
                    withAnimation { showTextInput.toggle() }
                } label: {
                    Image(systemName: showTextInput ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                micButton

                Spacer()

                // Auto-listen toggle
                Button {
                    viewModel.settings.autoListenEnabled.toggle()
                } label: {
                    Image(systemName: viewModel.settings.autoListenEnabled
                          ? "hands.and.sparkles.fill" : "hands.and.sparkles")
                        .font(.title2)
                        .foregroundStyle(viewModel.settings.autoListenEnabled ? .blue : .secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 4)
        }
    }

    // MARK: - Live transcript

    private var liveTranscriptView: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Text(viewModel.liveTranscript.isEmpty ? "Listening..." : viewModel.liveTranscript)
                .font(.caption)
                .foregroundStyle(viewModel.liveTranscript.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.06))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Mic button

    @ViewBuilder
    private var micButton: some View {
        if viewModel.settings.autoListenEnabled {
            // Auto mode: tap to pause the cycle, tap again to resume
            autoModeMicButton
        } else {
            // Manual mode: hold to speak
            MicButton(state: viewModel.conversationState) {
                viewModel.startListening()
            } onRelease: {
                viewModel.stopListeningAndSend()
            }
        }
    }

    private var autoModeMicButton: some View {
        Button {
            switch viewModel.conversationState {
            case .listening:
                // Cancel current listen cycle (pause)
                viewModel.cancelListening()
            case .idle:
                // Manually kick off a listen cycle
                viewModel.startListening()
            case .speaking:
                // Interrupt AI and start listening immediately
                viewModel.ttsService.stop()
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    viewModel.startListening()
                }
            default:
                break
            }
        } label: {
            ZStack {
                if case .listening = viewModel.conversationState {
                    Circle()
                        .stroke(Color.red.opacity(0.2), lineWidth: 4)
                        .frame(width: 96, height: 96)
                        .scaleEffect(1.08)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: UUID())
                }

                Circle()
                    .fill(autoButtonColor)
                    .frame(width: 72, height: 72)
                    .shadow(color: autoButtonColor.opacity(0.35), radius: 8, y: 4)

                Image(systemName: autoIconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var autoButtonColor: Color {
        switch viewModel.conversationState {
        case .idle:        return .gray
        case .listening:   return .red
        case .processing:  return .orange
        case .speaking:    return .green
        case .helpPaused:  return .blue
        case .error:       return .gray
        }
    }

    private var autoIconName: String {
        switch viewModel.conversationState {
        case .idle:        return "mic.slash.fill"
        case .listening:   return "waveform"
        case .processing:  return "ellipsis"
        case .speaking:    return "speaker.wave.2.fill"
        case .helpPaused:  return "mic.fill"
        case .error:       return "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Helpers

    private func submitText() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textInput = ""
        viewModel.sendText(trimmed)
    }
}

