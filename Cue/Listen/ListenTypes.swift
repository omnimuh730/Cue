import Foundation

nonisolated enum ListenPhase: String, Sendable {
    case off
    case armed
    case listening
    case transcribing
    case downloading
    case error
}

nonisolated struct ListenStatus: Equatable, Sendable {
    var phase: ListenPhase
    var armed: Bool
    var manualActive: Bool
    var model: WhisperModelID
    var mode: ListenMode
    var modelReady: Bool
    var downloadProgress: Double?
    var inputLevel: Double
    var audioAutoMode: Bool
    var error: String?
    var supported: Bool
    var liveCaptionsRunning: Bool
    var accessibilityTrusted: Bool

    static let idle = ListenStatus(
        phase: .off,
        armed: false,
        manualActive: false,
        model: .smallEn,
        mode: .whisper,
        modelReady: false,
        downloadProgress: nil,
        inputLevel: 0,
        audioAutoMode: true,
        error: nil,
        supported: true,
        liveCaptionsRunning: false,
        accessibilityTrusted: false
    )
}

protocol SpeechTranscribing: AnyObject, Sendable {
    func prepare(model: WhisperModelID, onProgress: @escaping @Sendable (Double) -> Void) async throws
    func transcribe(pcm: [Float], sampleRate: Int) async throws -> String
}

nonisolated enum AudioResampler {
    static func downsample(_ input: [Float], from fromRate: Int, to toRate: Int) -> [Float] {
        if fromRate == toRate { return input }
        let ratio = Double(fromRate) / Double(toRate)
        let outLength = Int(floor(Double(input.count) / ratio))
        guard outLength > 0 else { return [] }
        var out = [Float](repeating: 0, count: outLength)
        for i in 0..<outLength {
            let start = Int(floor(Double(i) * ratio))
            let end = min(input.count, Int(floor(Double(i + 1) * ratio)))
            let count = max(1, end - start)
            var sum: Float = 0
            for j in start..<end { sum += input[j] }
            out[i] = sum / Float(count)
        }
        return out
    }
}
