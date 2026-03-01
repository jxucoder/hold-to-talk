import Foundation

// MARK: - Shared debug file logger

private let debugLogFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

let debugLogPath: String = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("PushieTalkie")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("debug.log").path
}()

/// Maximum log file size before truncation (1 MB).
private let maxLogSize: UInt64 = 1_048_576

/// Truncates the debug log file if it exceeds `maxLogSize`.
/// Call once at app startup.
func truncateDebugLogIfNeeded() {
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

func debugLog(_ message: String) {
    let line = "[\(debugLogFormatter.string(from: Date()))] \(message)\n"
    print(message)
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: debugLogPath) {
            if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: debugLogPath, contents: data)
        }
    }
}
