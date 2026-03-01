import Foundation
import WhisperKit

struct WhisperModelInfo: Identifiable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let englishOnly: Bool

    static let all: [WhisperModelInfo] = [
        .init(id: "tiny.en",         displayName: "Tiny (English)",   sizeLabel: "~75 MB",   englishOnly: true),
        .init(id: "tiny",            displayName: "Tiny",             sizeLabel: "~75 MB",   englishOnly: false),
        .init(id: "base.en",         displayName: "Base (English)",   sizeLabel: "~140 MB",  englishOnly: true),
        .init(id: "base",            displayName: "Base",             sizeLabel: "~140 MB",  englishOnly: false),
        .init(id: "small.en",        displayName: "Small (English)",  sizeLabel: "~460 MB",  englishOnly: true),
        .init(id: "small",           displayName: "Small",            sizeLabel: "~460 MB",  englishOnly: false),
        .init(id: "medium",          displayName: "Medium",           sizeLabel: "~1.5 GB",  englishOnly: false),
        .init(id: "medium.en",       displayName: "Medium (English)", sizeLabel: "~1.5 GB",  englishOnly: true),
        // Fix #1: was "large-v3_turbo" (underscore) — mismatched the default "large-v3-turbo" in DictationEngine
        .init(id: "large-v3-turbo",  displayName: "Large V3 Turbo",  sizeLabel: "~1.6 GB",  englishOnly: false),
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
        let dir = appSupport.appendingPathComponent("PushieTalkie/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        refreshDownloadStatus()
    }

    func refreshDownloadStatus() {
        var found = Set<String>()
        // WhisperKit.download() creates a "models/" subdirectory inside downloadBase
        let repo = Self.modelBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: repo, includingPropertiesForKeys: nil
        ) else {
            downloaded = found
            return
        }

        for dir in contents {
            let name = dir.lastPathComponent
            let melSpec = dir.appendingPathComponent("MelSpectrogram.mlmodelc")
            guard FileManager.default.fileExists(atPath: melSpec.path) else { continue }

            if name.hasPrefix("openai_whisper-") {
                let modelId = String(name.dropFirst("openai_whisper-".count))
                found.insert(modelId)
            }
        }
        downloaded = found
    }

    // Fix #3: non-async; spawns a tracked task internally so it can be cancelled
    func download(_ modelId: String) {
        guard !downloading.contains(modelId) else { return }
        downloading.insert(modelId)
        downloadProgress[modelId] = 0
        downloadErrors.removeValue(forKey: modelId)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await WhisperKit.download(
                    variant: modelId,
                    downloadBase: Self.modelBase
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[modelId] = progress.fractionCompleted
                    }
                }
                if !Task.isCancelled {
                    downloaded.insert(modelId)
                }
            } catch {
                if !Task.isCancelled {
                    downloadErrors[modelId] = error.localizedDescription
                    print("[modelmanager] Download failed for \(modelId): \(error)")
                }
            }
            downloading.remove(modelId)
            downloadProgress.removeValue(forKey: modelId)
            downloadTasks.removeValue(forKey: modelId)
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
        let folder = Self.modelBase
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelId)")
        try? FileManager.default.removeItem(at: folder)
        downloaded.remove(modelId)
    }

    func diskSize(for modelId: String) -> String? {
        let folder = Self.modelBase
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelId)")
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        guard let bytes = directorySize(folder) else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
}
