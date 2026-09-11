import Foundation
import WhisperKit

final class WhisperRunner: SpeechTranscribing, @unchecked Sendable {
    private var kit: WhisperKit?
    private var loadedModel: WhisperModelID?

    func prepare(model: WhisperModelID, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if loadedModel == model, kit != nil {
            onProgress(1)
            return
        }
        onProgress(0.05)
        let config = WhisperKitConfig(model: model.whisperKitName, verbose: false, logLevel: .error)
        kit = try await WhisperKit(config)
        loadedModel = model
        onProgress(1)
    }

    func transcribe(pcm: [Float], sampleRate: Int) async throws -> String {
        guard let kit else {
            throw ChatError.transport("Whisper model is not ready.")
        }
        let resampled = AudioResampler.downsample(pcm, from: sampleRate, to: 16_000)
        let results = try await kit.transcribe(audioArray: resampled)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
