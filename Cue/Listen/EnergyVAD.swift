import Foundation

nonisolated enum VadEvent: Equatable, Sendable {
    case speechStart(atSample: Int)
    case speechEnd(startSample: Int, endSample: Int)
}

nonisolated struct EnergyVAD: Sendable {
    var sampleRate: Int
    var speechThreshold: Float
    var silenceThreshold: Float
    var minSpeechSamples: Int
    var minSilenceSamples: Int
    var maxSpeechSamples: Int
    var inSpeech = false
    var speechStartSample = 0
    var speechSamples = 0
    var silenceSamples = 0
    var absoluteSample = 0

    init(
        sampleRate: Int = 16_000,
        speechThreshold: Float = 0.006,
        silenceThreshold: Float = 0.003,
        minSpeechMs: Int = 180,
        minSilenceMs: Int = 350,
        maxSpeechMs: Int = 2_400
    ) {
        self.sampleRate = sampleRate
        self.speechThreshold = speechThreshold
        self.silenceThreshold = silenceThreshold
        self.minSpeechSamples = Int(Double(minSpeechMs) / 1000 * Double(sampleRate))
        self.minSilenceSamples = Int(Double(minSilenceMs) / 1000 * Double(sampleRate))
        self.maxSpeechSamples = Int(Double(maxSpeechMs) / 1000 * Double(sampleRate))
    }

    mutating func reset(absoluteSample: Int = 0) {
        inSpeech = false
        speechStartSample = absoluteSample
        speechSamples = 0
        silenceSamples = 0
        self.absoluteSample = absoluteSample
    }

    mutating func push(_ chunk: [Float], chunkStartAbsolute: Int) -> [VadEvent] {
        var events: [VadEvent] = []
        absoluteSample = chunkStartAbsolute
        let frameSize = max(1, sampleRate / 50)
        var offset = 0
        while offset < chunk.count {
            let end = min(chunk.count, offset + frameSize)
            var sum: Float = 0
            for i in offset..<end {
                sum += chunk[i] * chunk[i]
            }
            let rms = sqrt(sum / Float(max(1, end - offset)))
            let frameAbsolute = chunkStartAbsolute + offset
            let frameLen = end - offset

            if !inSpeech {
                if rms >= speechThreshold {
                    speechSamples += frameLen
                    if speechSamples >= minSpeechSamples {
                        inSpeech = true
                        speechStartSample = frameAbsolute - speechSamples + frameLen
                        silenceSamples = 0
                        events.append(.speechStart(atSample: speechStartSample))
                    }
                } else {
                    speechSamples = 0
                }
            } else {
                let spoken = frameAbsolute + frameLen - speechStartSample
                if spoken >= maxSpeechSamples {
                    let endSample = frameAbsolute + frameLen
                    events.append(.speechEnd(startSample: speechStartSample, endSample: endSample))
                    inSpeech = true
                    speechStartSample = endSample
                    speechSamples = 0
                    silenceSamples = 0
                    events.append(.speechStart(atSample: endSample))
                } else if rms <= silenceThreshold {
                    silenceSamples += frameLen
                    if silenceSamples >= minSilenceSamples {
                        let endSample = frameAbsolute + frameLen - silenceSamples
                        events.append(.speechEnd(startSample: speechStartSample, endSample: max(speechStartSample + 1, endSample)))
                        inSpeech = false
                        speechSamples = 0
                        silenceSamples = 0
                    }
                } else {
                    silenceSamples = 0
                }
            }
            absoluteSample = frameAbsolute + frameLen
            offset = end
        }
        return events
    }
}
