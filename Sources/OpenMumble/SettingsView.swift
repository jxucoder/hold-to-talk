import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @StateObject private var modelManager = ModelManager()
    @Environment(\.dismiss) private var dismiss

    @State private var showManageModels = false
    @State private var showCleanupPrompt = false

    private let hotkeys = HotkeyManager.Hotkey.allCases

    var body: some View {
        Form {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Group {
                        if let icon = OpenMumbleApp.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                        } else {
                            Image(systemName: "mic")
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(width: 64, height: 64)
                    Text("OpenMumble")
                        .font(.title2.bold())
                    Text("Free, open-source, and fully private — nothing leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/jxucoder/openmumble")!) {
                            Image(systemName: "star")
                                .font(.caption)
                        }
                        Link(destination: URL(string: "https://buymeacoffee.com/jerryxu")!) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            Section("Whisper Model") {
                Picker("Active model", selection: $engine.whisperModel) {
                    ForEach(sortedModels) { model in
                        HStack {
                            Text(model.displayName)
                            if !modelManager.downloaded.contains(model.id) {
                                Text("(not downloaded)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .tag(model.id)
                    }
                }

                DisclosureGroup(isExpanded: $showManageModels) {
                    modelListView
                } label: {
                    Text("Manage Models")
                }
                .contentShape(Rectangle())
                .onTapGesture { showManageModels.toggle() }
            }

            Section("Cleanup") {
                Toggle("Enable cleanup", isOn: $engine.cleanupEnabled)

                if TextProcessor.isAvailable {
                    Label("Apple Intelligence (on-device)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Requires macOS 26+ with Apple Intelligence", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup(isExpanded: $showCleanupPrompt) {
                    TextEditor(text: $engine.cleanupPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.quaternary)
                                )
                        )

                    if engine.cleanupPrompt != TextProcessor.defaultPrompt {
                        Button("Reset to default") {
                            engine.cleanupPrompt = TextProcessor.defaultPrompt
                        }
                        .controlSize(.small)
                    }
                } label: {
                    Text("Cleanup prompt")
                }
                .contentShape(Rectangle())
                .onTapGesture { showCleanupPrompt.toggle() }
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
        .frame(width: 420, height: 580)
        .padding()
        .onAppear {
            modelManager.refreshDownloadStatus()
        }
    }

    // MARK: - Model list

    private var sortedModels: [WhisperModelInfo] {
        // Fix #16: stable sort — downloaded first, then alphabetical by id
        WhisperModelInfo.all.sorted { a, b in
            let aDown = modelManager.downloaded.contains(a.id)
            let bDown = modelManager.downloaded.contains(b.id)
            if aDown != bDown { return aDown }
            return a.id < b.id
        }
    }

    private var modelListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WhisperModelInfo.all) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: WhisperModelInfo) -> some View {
        let isDownloaded = modelManager.downloaded.contains(model.id)
        let isDownloading = modelManager.downloading.contains(model.id)
        let isActive = engine.whisperModel == model.id

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(model.displayName)
                            .fontWeight(isActive ? .semibold : .regular)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue, in: Capsule())
                        }
                    }
                    Text(isDownloaded
                         ? (modelManager.diskSize(for: model.id) ?? model.sizeLabel)
                         : model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !isActive {
                            Button(role: .destructive) {
                                modelManager.delete(model.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else if isDownloading {
                    Button("Cancel") {
                        modelManager.cancelDownload(model.id)
                    }
                    .controlSize(.small)
                } else {
                    Button("Download") {
                        modelManager.download(model.id)
                    }
                    .controlSize(.small)
                }
            }

            if isDownloading, let progress = modelManager.downloadProgress[model.id] {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = modelManager.downloadErrors[model.id] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

}
