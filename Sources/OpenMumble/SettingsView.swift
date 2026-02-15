import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @Environment(\.dismiss) private var dismiss

    private let models = ["tiny.en", "base.en", "small.en", "medium", "large-v3"]
    private let hotkeys = HotkeyManager.Hotkey.allCases

    var body: some View {
        Form {
            Section("Whisper") {
                Picker("Model", selection: $engine.whisperModel) {
                    ForEach(models, id: \.self) { Text($0) }
                }
            }

            Section("Claude cleanup") {
                Toggle("Enable cleanup", isOn: $engine.cleanupEnabled)
                SecureField("API key", text: $engine.claudeApiKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $engine.claudeModel)
                    .textFieldStyle(.roundedBorder)
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
        .frame(width: 360, height: 340)
        .padding()
    }
}
