import SwiftUI

struct SettingsView: View {

    @ObservedObject var viewModel: SettingsViewModel
    @State private var showAPIKey = false
    @State private var showTTSKey = false

    var body: some View {
        NavigationView {
            Form {
                aiSection
                ttsSection
                handsFreeSection
                voiceSection
                difficultySection
                tipsSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - AI Backend

    private var aiSection: some View {
        Section("AI Backend") {
            HStack {
                Text("API Key")
                Spacer()
                if showAPIKey {
                    TextField("Paste Gemini key", text: $viewModel.settings.apiKey)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.primary)
                } else {
                    Text(viewModel.settings.apiKey.isEmpty ? "Not set" : "••••••••")
                        .foregroundStyle(viewModel.settings.apiKey.isEmpty ? .red : .secondary)
                }
                Button(showAPIKey ? "Hide" : "Edit") {
                    showAPIKey.toggle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            LabeledContent("Server URL") {
                TextField("API base URL", text: $viewModel.settings.apiBaseURL)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption)
            }

            LabeledContent("Model") {
                TextField("Model name", text: $viewModel.settings.modelName)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Button {
                Task { await viewModel.testConnection() }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if viewModel.isTesting {
                        ProgressView().scaleEffect(0.8)
                    } else if let result = viewModel.connectionResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? .green : .red)
                        Text(result ? "Connected" : "Failed")
                            .font(.caption)
                            .foregroundStyle(result ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - TTS

    private var ttsSection: some View {
        Section {
            HStack {
                Text("ElevenLabs Key")
                Spacer()
                if showTTSKey {
                    TextField("Paste key", text: $viewModel.settings.elevenLabsKey)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    Text(viewModel.settings.elevenLabsKey.isEmpty ? "Not set" : "••••••••")
                        .foregroundStyle(viewModel.settings.elevenLabsKey.isEmpty ? .orange : .secondary)
                }
                Button(showTTSKey ? "Hide" : "Edit") { showTTSKey.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
            if viewModel.settings.elevenLabsKey.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.orange)
                    Text("Add an ElevenLabs key for natural neural voices. Without it, device TTS is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.elevenLabsVoices.isEmpty {
                Picker("Voice", selection: $viewModel.settings.elevenLabsVoiceID) {
                    Text("Auto").tag("")
                    ForEach(viewModel.elevenLabsVoices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
            }
        } header: {
            Text("Voice Engine")
        }
    }

    // MARK: - Hands-free

    private var handsFreeSection: some View {
        Section("Hands-Free Mode") {
            Toggle(isOn: $viewModel.settings.autoListenEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Listen")
                    Text("Mic turns on automatically after AI speaks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            if viewModel.settings.autoListenEnabled {
                HStack {
                    Image(systemName: "info.circle").foregroundStyle(.blue)
                    Text("Tap the mic button anytime to pause or interrupt the AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section("Voice & Speed") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speaking Speed")
                    Spacer()
                    Text(speedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $viewModel.settings.ttsRate, in: 0.20...0.65, step: 0.02)
                    .tint(.blue)
                HStack {
                    Text("Slow").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Natural").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Fast").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)

            Button("Preview Korean Voice") {
                viewModel.previewVoice()
            }
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        Section("Difficulty") {
            Picker("Level", selection: $viewModel.settings.difficultyLevel) {
                ForEach(DifficultyLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        Section("Voice Commands") {
            tipRow(icon: "questionmark.circle.fill", color: .blue,
                   text: "Say **\"help\"** — AI explains in English, then pauses")
            tipRow(icon: "arrow.right.circle.fill", color: .green,
                   text: "Say **\"continue\"** — resume Korean conversation")
            tipRow(icon: "tortoise.fill", color: .orange,
                   text: "Say **\"slower\"** or **\"faster\"** to adjust speech speed")
            tipRow(icon: "chart.bar.fill", color: .purple,
                   text: "Say **\"harder\"** or **\"easier\"** to change difficulty")
        }
    }

    private func tipRow(icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private var speedLabel: String {
        let r = viewModel.settings.ttsRate
        switch r {
        case ..<0.32: return "Slow"
        case 0.32..<0.50: return "Natural"
        default: return "Fast"
        }
    }
}
