import AVFoundation

/// Captures microphone audio into a 16 kHz mono float buffer for Whisper.
/// Thread-safe via NSLock; marked Sendable for cross-actor usage.
///
/// The audio engine is pre-warmed on `prepare()` so that `start()` only installs
/// a tap and resumes — cutting hotkey-to-recording latency from ~150ms to <10ms.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private var isPrepared = false

    /// Pre-warms the audio engine so subsequent start() calls are near-instant.
    /// Call once at app startup. Safe to call multiple times.
    func prepare() {
        lock.lock()
        guard !isPrepared else { lock.unlock(); return }
        isPrepared = true
        lock.unlock()
        // Accessing inputNode implicitly connects it to the engine graph.
        _ = engine.inputNode
        engine.prepare()
    }

    func start() throws {
        lock.lock()
        buffers.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Fix #8: use safe conditional cast — force-cast crashes if copy() returns unexpected type
            guard let copied = buffer.copy() as? AVAudioPCMBuffer else { return }
            self.lock.lock()
            self.buffers.append(copied)
            self.lock.unlock()
        }

        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Re-prepare so the next start() is fast again
        engine.prepare()

        lock.lock()
        let captured = buffers
        buffers.removeAll()
        lock.unlock()

        guard !captured.isEmpty else { return [] }
        return resample(buffers: captured)
    }

    // MARK: - Resampling

    /// Concatenates captured buffers and resamples to 16 kHz mono for Whisper.
    private func resample(buffers: [AVAudioPCMBuffer]) -> [Float] {
        let srcFormat = buffers[0].format
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }

        guard let combined = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            return []
        }
        for buf in buffers {
            guard let dst = combined.floatChannelData?[0].advanced(by: Int(combined.frameLength)),
                  let src = buf.floatChannelData?[0] else { continue }
            dst.update(from: src, count: Int(buf.frameLength))
            combined.frameLength += buf.frameLength
        }

        // If already 16 kHz mono, skip conversion
        if Int(srcFormat.sampleRate) == 16000 && srcFormat.channelCount == 1 {
            return Array(UnsafeBufferPointer(start: combined.floatChannelData?[0],
                                             count: Int(combined.frameLength)))
        }

        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            return Array(UnsafeBufferPointer(start: combined.floatChannelData?[0],
                                             count: Int(combined.frameLength)))
        }

        let ratio = 16000.0 / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(combined.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outCapacity) else {
            return []
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return combined
        }

        if let error {
            print("[audio] resample error: \(error)")
            return []
        }

        return Array(UnsafeBufferPointer(start: output.floatChannelData?[0],
                                         count: Int(output.frameLength)))
    }
}
