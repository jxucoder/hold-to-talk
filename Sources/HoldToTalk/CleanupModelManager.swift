import Foundation

struct CleanupModelInfo {
    static let id = "gemma-3-1b-it-Q4_K_M"
    static let displayName = "Gemma 3 1B"
    static let sizeLabel = "~806 MB"
    static let fileName = "google_gemma-3-1b-it-Q4_K_M.gguf"

    static let downloadURL = URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf")!
    static let huggingFaceURL = URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF")!
    static let gemmaURL = URL(string: "https://ai.google.dev/gemma")!

    static let trustSummary = "Runs fully on your Mac after download. Hold to Talk downloads Google's Gemma 3 1B model (Q4_K_M quantized) from HuggingFace. The model is open-weight (Gemma license) and used only for grammar cleanup."
}

@MainActor
final class CleanupModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var isDownloaded: Bool = false
    @Published var downloadError: String?

    private var downloadTask: Task<Void, Never>?

    var modelFilePath: URL {
        ModelManager.modelBase.appendingPathComponent(CleanupModelInfo.fileName)
    }

    init() {
        refreshDownloadStatus()
    }

    func refreshDownloadStatus() {
        isDownloaded = FileManager.default.fileExists(atPath: modelFilePath.path)
    }

    func handleFreshOnboardingReset() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        downloadError = nil
        refreshDownloadStatus()
    }

    func download() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let tempFileURL = try await self.downloadFile()
                if Task.isCancelled { return }
                let fm = FileManager.default
                let dest = self.modelFilePath
                // Remove any partial previous download
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: tempFileURL, to: dest)
                if !Task.isCancelled {
                    await MainActor.run { self.isDownloaded = true }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.downloadError = self.userFacingDownloadError(error)
                    }
                    print("[cleanup-model] Download failed: \(error)")
                }
            }
            await MainActor.run {
                self.isDownloading = false
                self.downloadProgress = 0
                self.downloadTask = nil
            }
        }
        downloadTask = task
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }

    func deleteModel() {
        let path = modelFilePath
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
        }
        isDownloaded = false
        Task { await TextProcessorEngine.shared.unload() }
    }

    func diskSize() -> String? {
        let path = modelFilePath
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? UInt64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: - Private

    private func downloadFile() async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(
            from: CleanupModelInfo.downloadURL,
            delegate: DownloadProgressDelegate { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = fraction
                }
            }
        )
        return tempURL
    }

    private func userFacingDownloadError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()

        if lower.contains("timed out")
            || lower.contains("network connection was lost")
            || lower.contains("internet")
            || lower.contains("offline") {
            return "Download failed due to a network issue. Check your connection and try again."
        }

        return message
    }
}
