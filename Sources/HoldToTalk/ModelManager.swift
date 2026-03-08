import Foundation
import WhisperKit

struct WhisperModelInfo: Identifiable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let englishOnly: Bool

    static let defaultModelID = "large-v3_turbo"

    /// Maps legacy IDs to WhisperKit-compatible variant names.
    static func normalizeModelID(_ id: String) -> String {
        switch id {
        case "large-v3-turbo":
            return "large-v3_turbo"
        default:
            return id
        }
    }

    /// Normalizes downloaded folder variants (e.g. strips "_954MB" suffix).
    static func normalizeDownloadedVariant(_ id: String) -> String {
        let normalized = normalizeModelID(id)
        return normalized.replacingOccurrences(
            of: "_[0-9]+MB$",
            with: "",
            options: .regularExpression
        )
    }

    /// Converts WhisperKit support strings into app model IDs.
    static func modelID(fromSupportEntry rawEntry: String) -> String? {
        let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return nil }

        // Support entries are typically "openai_whisper-<variant>".
        if entry.hasPrefix("openai_whisper-") {
            let suffix = String(entry.dropFirst("openai_whisper-".count))
            return normalizeDownloadedVariant(suffix)
        }

        // Ignore distil variants for now; app UX currently targets openai variants only.
        if entry.hasPrefix("distil-whisper_") {
            return nil
        }

        return normalizeDownloadedVariant(entry)
    }

    /// Returns a device-aware model profile based on WhisperKit's support matrix.
    static func deviceModelProfile() -> (available: [WhisperModelInfo], recommendedID: String) {
        let support = WhisperKit.recommendedModels()
        let supportedIDs = Set(support.supported.compactMap(modelID(fromSupportEntry:)))

        let available = all.filter { supportedIDs.contains($0.id) }
        let resolvedAvailable = available.isEmpty ? all : available
        let availableIDs = Set(resolvedAvailable.map(\.id))

        let recommendedFromSupport = modelID(fromSupportEntry: support.default)
        if let recommendedFromSupport, availableIDs.contains(recommendedFromSupport) {
            return (resolvedAvailable, recommendedFromSupport)
        }
        if availableIDs.contains(defaultModelID) {
            return (resolvedAvailable, defaultModelID)
        }
        if availableIDs.contains("small.en") {
            return (resolvedAvailable, "small.en")
        }
        return (resolvedAvailable, resolvedAvailable.first?.id ?? defaultModelID)
    }

    static let all: [WhisperModelInfo] = [
        .init(id: "tiny.en",         displayName: "Tiny (English)",   sizeLabel: "~75 MB",   englishOnly: true),
        .init(id: "tiny",            displayName: "Tiny",             sizeLabel: "~75 MB",   englishOnly: false),
        .init(id: "base.en",         displayName: "Base (English)",   sizeLabel: "~140 MB",  englishOnly: true),
        .init(id: "base",            displayName: "Base",             sizeLabel: "~140 MB",  englishOnly: false),
        .init(id: "small.en",        displayName: "Small (English)",  sizeLabel: "~460 MB",  englishOnly: true),
        .init(id: "small",           displayName: "Small",            sizeLabel: "~460 MB",  englishOnly: false),
        .init(id: "medium",          displayName: "Medium",           sizeLabel: "~1.5 GB",  englishOnly: false),
        .init(id: "medium.en",       displayName: "Medium (English)", sizeLabel: "~1.5 GB",  englishOnly: true),
        .init(id: "large-v3_turbo",  displayName: "Large V3 Turbo",  sizeLabel: "~1.6 GB",  englishOnly: false),
        .init(id: "large-v3-v20240930", displayName: "Large V3 (20240930)", sizeLabel: "~626 MB", englishOnly: false),
        .init(id: "large-v3-v20240930_turbo", displayName: "Large V3 (20240930 Turbo)", sizeLabel: "~632 MB", englishOnly: false),
        .init(id: "large-v3",        displayName: "Large V3",        sizeLabel: "~3 GB",    englishOnly: false),
    ]
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloading: Set<String> = []
    @Published var downloaded: Set<String> = []
    @Published var downloadErrors: [String: String] = [:]

    // Fix #3: track live download tasks so cancelDownload() actually stops them
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    static let modelBase: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("HoldToTalk/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        refreshDownloadStatus()
    }

    private var repoURL: URL {
        Self.modelBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }

    private func modelFolders(matching modelId: String) -> [URL] {
        let normalizedID = WhisperModelInfo.normalizeModelID(modelId)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: repoURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.filter { dir in
            let name = dir.lastPathComponent
            guard name.hasPrefix("openai_whisper-") else { return false }
            let raw = String(name.dropFirst("openai_whisper-".count))
            let normalized = WhisperModelInfo.normalizeDownloadedVariant(raw)
            return normalized == normalizedID
        }
    }

    func refreshDownloadStatus() {
        var found = Set<String>()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: repoURL, includingPropertiesForKeys: nil
        ) else {
            downloaded = found
            return
        }

        for dir in contents {
            let name = dir.lastPathComponent
            let melSpec = dir.appendingPathComponent("MelSpectrogram.mlmodelc")
            guard FileManager.default.fileExists(atPath: melSpec.path) else { continue }

            if name.hasPrefix("openai_whisper-") {
                let rawModelID = String(name.dropFirst("openai_whisper-".count))
                let modelId = WhisperModelInfo.normalizeDownloadedVariant(rawModelID)
                found.insert(modelId)
            }
        }
        downloaded = found
    }

    // Fix #3: non-async; spawns a tracked task internally so it can be cancelled
    func download(_ modelId: String) {
        // Normalize up-front so all state keys (downloading, downloaded, downloadProgress, etc.)
        // are stored under the canonical ID, avoiding raw-vs-normalized mismatches.
        let modelId = WhisperModelInfo.normalizeModelID(modelId)
        guard !downloading.contains(modelId) else { return }
        downloading.insert(modelId)
        downloadProgress[modelId] = 0
        downloadErrors.removeValue(forKey: modelId)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await WhisperKit.download(
                    variant: modelId,   // already normalized
                    downloadBase: Self.modelBase
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[modelId] = progress.fractionCompleted
                    }
                }
                if !Task.isCancelled {
                    await MainActor.run { _ = self.downloaded.insert(modelId) }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.downloadErrors[modelId] = self.userFacingDownloadError(error)
                    }
                    print("[modelmanager] Download failed for \(modelId): \(error)")
                }
            }
            await MainActor.run {
                self.downloading.remove(modelId)
                self.downloadProgress.removeValue(forKey: modelId)
                self.downloadTasks.removeValue(forKey: modelId)
            }
        }
        downloadTasks[modelId] = task
    }

    func cancelDownload(_ modelId: String) {
        // Fix #3: actually cancel the running Task, not just clear UI state
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        downloading.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)
    }

    func delete(_ modelId: String) {
        let folders = modelFolders(matching: modelId)
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        downloaded.remove(WhisperModelInfo.normalizeModelID(modelId))
    }

    func diskSize(for modelId: String) -> String? {
        let folders = modelFolders(matching: modelId)
        guard !folders.isEmpty else { return nil }
        let total = folders.compactMap(directorySize).reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private func directorySize(_ url: URL) -> UInt64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func userFacingDownloadError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()

        if lower.contains("no models found matching")
            || lower.contains("models are unavailable")
            || lower.contains("models unavailable") {
            return "Model variant unavailable. Choose another model or switch to the recommended model for this Mac."
        }
        if lower.contains("timed out")
            || lower.contains("network connection was lost")
            || lower.contains("internet")
            || lower.contains("offline") {
            return "Download failed due to a network issue. Check your connection and try again."
        }

        return message
    }
}
