import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("onboardingStep") private var step = 0
    @State private var hasMicrophone = false
    @State private var hasAccessibility = false
    @State private var hasInputMonitoring = false
    @State private var downloadStarted = false
    @State private var hasShownAccessibilityPrompt = false
    @State private var hasShownInputMonitoringPrompt = false
    @StateObject private var hotkeyTester = HotkeyTester()

    init(engine: DictationEngine, modelManager: ModelManager) {
        self.engine = engine
        self.modelManager = modelManager
        #if DEBUG
        if let override = DebugFlags.onboardingStep {
            let clamped = max(0, min(override, 3))
            UserDefaults.standard.set(clamped, forKey: "onboardingStep")
            print("[debug] Starting onboarding at step \(clamped).")
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: modelStep
                default: readyStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()
        }
        .frame(width: 480, height: 520)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            appIcon
                .frame(width: 80, height: 80)

            Text("Welcome to PushieTalkie")
                .font(.title.bold())

            Text("Voice dictation that runs entirely on your Mac.\nHold a key, speak, release — your words appear wherever your cursor is.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Get Started") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.title2.bold())

            Text("PushieTalkie needs a few permissions to work.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Record your voice for transcription",
                    granted: hasMicrophone
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        Task { @MainActor in hasMicrophone = granted }
                    }
                }

                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Paste text into the active app",
                    granted: hasAccessibility
                ) {
                    if !hasShownAccessibilityPrompt {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(opts)
                        hasShownAccessibilityPrompt = true
                    } else {
                        openSystemSettings("Privacy_Accessibility")
                    }
                }

                permissionRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    subtitle: "Listen for your hotkey globally",
                    granted: hasInputMonitoring
                ) {
                    if !hasShownInputMonitoringPrompt {
                        _ = CGRequestListenEventAccess()
                        hasShownInputMonitoringPrompt = true
                        UserDefaults.standard.set(true, forKey: "hasPromptedInputMonitoring")
                    } else {
                        openSystemSettings("Privacy_ListenEvent")
                    }
                }
            }
            .padding(.horizontal, 16)

            Button("Continue") {
                step = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasMicrophone || !hasAccessibility)
            .padding(.top, 8)

            if !hasMicrophone || !hasAccessibility {
                Text("Grant Microphone and Accessibility to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            VStack(spacing: 6) {
                Text("Dev builds can't detect Accessibility grants (unsigned binary).")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("Skip Permissions (Debug)") {
                    hasMicrophone = true
                    hasAccessibility = true
                    hasInputMonitoring = true
                    engine.hasAccessibility = true
                    step = 2
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
            #endif
        }
        .padding(32)
        .task {
            // Structured concurrency replaces Timer — auto-cancels when view disappears
            refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.06) : Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Step 3: Model Download

    private var modelStep: some View {
        VStack(spacing: 20) {
            Text("Download Model")
                .font(.title2.bold())

            Text("PushieTalkie needs a speech recognition model.\nPick one to download — you can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Picker("Model", selection: $engine.whisperModel) {
                ForEach(WhisperModelInfo.all) { model in
                    Text("\(model.displayName)  (\(model.sizeLabel))")
                        .tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 280)

            let modelId = engine.whisperModel
            let isDownloaded = modelManager.downloaded.contains(modelId)
            let isDownloading = modelManager.downloading.contains(modelId)

            if isDownloaded {
                Label("Ready to use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else if isDownloading {
                VStack(spacing: 8) {
                    if let progress = modelManager.downloadProgress[modelId] {
                        ProgressView(value: progress)
                            .frame(width: 280)
                        Text("Downloading... \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Starting download...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Download \(modelDisplayName(modelId))") {
                    modelManager.download(modelId)
                    downloadStarted = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let error = modelManager.downloadErrors[modelId] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 320)
            }

            Button("Continue") {
                step = 3
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isDownloaded)
            .padding(.top, 4)
        }
        .padding(32)
        .onAppear {
            modelManager.refreshDownloadStatus()
            let modelId = engine.whisperModel
            if !modelManager.downloaded.contains(modelId) && !modelManager.downloading.contains(modelId) {
                modelManager.download(modelId)
                downloadStarted = true
            }
        }
        .onChange(of: engine.whisperModel) {
            let modelId = engine.whisperModel
            modelManager.refreshDownloadStatus()
            if !modelManager.downloaded.contains(modelId) && !modelManager.downloading.contains(modelId) {
                modelManager.download(modelId)
            }
        }
    }

    // MARK: - Step 4: Ready

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey(rawValue: engine.hotkeyChoice) ?? .ctrl
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Text("You're All Set")
                .font(.title2.bold())

            VStack(spacing: 16) {
                // Hotkey picker
                VStack(spacing: 8) {
                    Text("Hold this key to record:")
                        .font(.body)

                    Picker("Hotkey", selection: $engine.hotkeyChoice) {
                        ForEach(HotkeyManager.Hotkey.allCases, id: \.rawValue) { key in
                            Text(key.rawValue).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    .onChange(of: engine.hotkeyChoice) {
                        engine.reloadHotkey()
                        hotkeyTester.remove()
                        hotkeyTester.install(for: resolvedHotkey)
                    }
                }

                // Interactive hotkey test area
                VStack(spacing: 8) {
                    switch hotkeyTester.phase {
                    case .waiting:
                        Image(systemName: "keyboard")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Press and hold [\(engine.hotkeyChoice)] to test")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .holding:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                            .symbolEffect(.pulse)
                        Text("Holding [\(engine.hotkeyChoice)]… release to finish")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Hotkey works! You're ready to go.")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
                .frame(height: 80)
                .animation(.easeInOut(duration: 0.2), value: hotkeyTester.phase)

                // Menu bar hint
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.caption.bold())
                    Text("PushieTalkie lives in your menu bar")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }

            Button("Start Using PushieTalkie") {
                step = 0
                engine.completeOnboarding()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
        .onAppear {
            hotkeyTester.install(for: resolvedHotkey)
        }
        .onDisappear {
            hotkeyTester.remove()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var appIcon: some View {
        if let icon = PushieTalkieApp.appIcon {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "mic.circle.fill")
                .resizable()
                .foregroundStyle(Color.accentColor)
        }
    }

    private func modelDisplayName(_ id: String) -> String {
        WhisperModelInfo.all.first { $0.id == id }?.displayName ?? id
    }

    private func refreshPermissions() {
        #if DEBUG
        if DebugFlags.skipPermissions {
            hasMicrophone = true
            hasAccessibility = true
            hasInputMonitoring = true
            engine.hasAccessibility = true
            return
        }
        #endif
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = CGPreflightListenEventAccess()
        engine.hasAccessibility = hasAccessibility
    }

    // openSystemSettings is now a shared top-level function in SystemSettingsHelper.swift
}

// MARK: - HotkeyTester

@MainActor
private final class HotkeyTester: ObservableObject {
    enum Phase {
        case waiting, holding, success
    }

    @Published var phase: Phase = .waiting

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotkey: HotkeyManager.Hotkey = .ctrl

    func install(for hotkey: HotkeyManager.Hotkey) {
        remove()
        self.hotkey = hotkey
        phase = .waiting

        let handler: (NSEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
            return event
        }
    }

    func remove() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    private func handle(_ event: NSEvent) {
        let flagsMatch = event.modifierFlags.contains(hotkey.flag)
        let pressed: Bool
        if let requiredCode = hotkey.keyCode {
            pressed = flagsMatch && event.keyCode == requiredCode
        } else {
            pressed = flagsMatch
        }

        if pressed && phase == .waiting {
            phase = .holding
        } else if !pressed && phase == .holding {
            phase = .success
        }
    }
}
