import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var availableCleanupModels: [String] = []
    @State private var isLoadingCleanupModels = false
    @State private var modelLoadStatus: String?

    private let models = ["tiny.en", "base.en", "small.en", "medium", "large-v3"]
    private let hotkeys = HotkeyManager.Hotkey.allCases
    private let providers = TextProcessor.Provider.allCases

    var body: some View {
        Form {
            Section("Whisper") {
                Picker("Model", selection: $engine.whisperModel) {
                    ForEach(models, id: \.self) { Text($0) }
                }
            }

            Section("Cleanup") {
                Toggle("Enable cleanup", isOn: $engine.cleanupEnabled)

                Picker("Provider", selection: $engine.cleanupProvider) {
                    ForEach(providers, id: \.rawValue) { p in
                        Text(p.rawValue.capitalized).tag(p.rawValue)
                    }
                }
                .onChange(of: engine.cleanupProvider) {
                    availableCleanupModels = []
                    modelLoadStatus = nil
                }

                if engine.cleanupProvider == "claude" {
                    SecureField("Claude API key", text: $engine.claudeApiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Claude model", text: $engine.claudeModel)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("OpenAI API key", text: $engine.openaiApiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("OpenAI model", text: $engine.openaiModel)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("Load available models") {
                        Task { await loadAvailableModels() }
                    }
                    .disabled(isLoadingCleanupModels)

                    if isLoadingCleanupModels {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !availableCleanupModels.isEmpty {
                    Picker("Available models", selection: selectedCleanupModelBinding) {
                        ForEach(availableCleanupModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if let modelLoadStatus {
                    Text(modelLoadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Hotkey") {
                Picker("Hold to record", selection: $engine.hotkeyChoice) {
                    ForEach(hotkeys, id: \.rawValue) { key in
                        Text(key.rawValue).tag(key.rawValue)
                    }
                }
                .onChange(of: engine.hotkeyChoice) {
                    engine.reloadHotkey()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 380)
        .padding()
    }

    private var selectedProvider: TextProcessor.Provider {
        TextProcessor.Provider(rawValue: engine.cleanupProvider) ?? .claude
    }

    private var selectedAPIKey: String {
        switch selectedProvider {
        case .claude:
            return engine.claudeApiKey
        case .openai:
            return engine.openaiApiKey
        }
    }

    private var selectedCleanupModelBinding: Binding<String> {
        switch selectedProvider {
        case .claude:
            return $engine.claudeModel
        case .openai:
            return $engine.openaiModel
        }
    }

    @MainActor
    private func loadAvailableModels() async {
        let key = selectedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            modelLoadStatus = "Enter an API key first."
            availableCleanupModels = []
            return
        }

        isLoadingCleanupModels = true
        defer { isLoadingCleanupModels = false }

        do {
            let processor = TextProcessor(
                provider: selectedProvider,
                apiKey: key,
                model: selectedCleanupModelBinding.wrappedValue
            )
            let models = try await processor.fetchAvailableModels()
            availableCleanupModels = models
            modelLoadStatus = models.isEmpty ? "No models returned." : "Loaded \(models.count) models."
        } catch {
            availableCleanupModels = []
            modelLoadStatus = "Could not load models: \(error.localizedDescription)"
        }
    }
}
