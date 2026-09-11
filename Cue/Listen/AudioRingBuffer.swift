import Foundation

nonisolated final class AudioRingBuffer: @unchecked Sendable {
    private var samples: [Float]
    private var writeIndex = 0
    private var totalWritten = 0
    private var watermarkSample = 0
    let sampleRate: Int

    init(sampleRate: Int = 16_000, capacitySeconds: Int = 180) {
        self.sampleRate = sampleRate
        self.samples = Array(repeating: 0, count: max(1, sampleRate * capacitySeconds))
    }

    var nowSample: Int { totalWritten }

    var watermarkSampleIndex: Int { watermarkSample }

    func push(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        for sample in chunk {
            samples[writeIndex] = sample
            writeIndex = (writeIndex + 1) % samples.count
            totalWritten += 1
        }
        let oldest = max(0, totalWritten - samples.count)
        if watermarkSample < oldest { watermarkSample = oldest }
    }

    func setWatermark(sample: Int) {
        let oldest = max(0, totalWritten - samples.count)
        watermarkSample = min(totalWritten, max(oldest, sample))
    }

    func resetToNow() {
        watermarkSample = totalWritten
    }

    func clear() {
        samples = Array(repeating: 0, count: samples.count)
        writeIndex = 0
        totalWritten = 0
        watermarkSample = 0
    }

    func slice(startSample: Int, endSample: Int) -> [Float]? {
        var start = startSample
        var end = endSample
        if end <= start { return nil }
        let oldest = max(0, totalWritten - samples.count)
        if start < oldest { start = oldest }
        if end > totalWritten { end = totalWritten }
        if end <= start { return nil }
        let length = end - start
        var out = [Float](repeating: 0, count: length)
        for i in 0..<length {
            out[i] = samples[(start + i) % samples.count]
        }
        return out
    }
}
