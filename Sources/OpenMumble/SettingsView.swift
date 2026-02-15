import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @Environment(\.dismiss) private var dismiss

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
}
