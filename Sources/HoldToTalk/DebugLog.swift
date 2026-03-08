import Foundation

// MARK: - Shared debug file logger

private let debugLogFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

let debugLogPath: String = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("HoldToTalk")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("debug.log").path
}()

/// Maximum log file size before truncation (1 MB).
private let maxLogSize: UInt64 = 1_048_576

/// Serial queue that serializes all log writes — prevents concurrent corruption from multiple callers
/// (main actor, audio tap callbacks, background transcription tasks, etc.).
private let logQueue = DispatchQueue(label: "com.holdtotalk.debuglog", qos: .utility)

/// Persistent write handle — avoids opening/closing the file on every log line.
/// Accessed only from `logQueue`.
private var _logHandle: FileHandle?

func isDiagnosticLoggingEnabled(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: diagnosticLoggingEnabledDefaultsKey)
}

func diagnosticLogRedactionSummary(for text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "<redacted empty>" }
    let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
    return "<redacted \(trimmed.count) chars, \(wordCount) words>"
}

private func ensureLogHandle() -> FileHandle? {
    if let handle = _logHandle { return handle }
    if !FileManager.default.fileExists(atPath: debugLogPath) {
        FileManager.default.createFile(atPath: debugLogPath, contents: nil)
    }
    let handle = FileHandle(forWritingAtPath: debugLogPath)
    handle?.seekToEndOfFile()
    _logHandle = handle
    return handle
}

/// Truncates the debug log file if it exceeds `maxLogSize`.
/// Call once at app startup. Runs synchronously on `logQueue` so it completes before the
/// first `debugLog()` call, and the persistent handle is always opened on a clean file.
func truncateDebugLogIfNeeded() {
    logQueue.sync {
        // Close the persistent handle so we can safely replace file contents.
        _logHandle?.closeFile()
        _logHandle = nil

        guard FileManager.default.fileExists(atPath: debugLogPath),
              let attrs = try? FileManager.default.attributesOfItem(atPath: debugLogPath),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }
        guard let data = FileManager.default.contents(atPath: debugLogPath) else { return }
        let keepFrom = data.count / 2
        let trimmed = data.subdata(in: keepFrom..<data.count)
        if let newlineIndex = trimmed.firstIndex(of: UInt8(ascii: "\n")) {
            let clean = trimmed.subdata(in: trimmed.index(after: newlineIndex)..<trimmed.endIndex)
            try? clean.write(to: URL(fileURLWithPath: debugLogPath))
        } else {
            try? trimmed.write(to: URL(fileURLWithPath: debugLogPath))
        }
    }
}

func clearDebugLog(fileManager: FileManager = .default) {
    logQueue.sync {
        _logHandle?.closeFile()
        _logHandle = nil
        guard fileManager.fileExists(atPath: debugLogPath) else { return }
        try? fileManager.removeItem(atPath: debugLogPath)
    }
}

func debugLogSensitive(_ label: String, text: String) {
    debugLog("\(label): \(diagnosticLogRedactionSummary(for: text))")
}

func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
    guard isDiagnosticLoggingEnabled() else { return }
    let line = "[\(debugLogFormatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    // Async dispatch — callers are never blocked waiting for disk I/O.
    logQueue.async {
        guard let handle = ensureLogHandle() else { return }
        handle.write(data)
    }
}
