import Foundation
import OSLog
import WhisperKit

nonisolated final class WhisperRunner: SpeechTranscribing, @unchecked Sendable {
    private var kit: WhisperKit?
    private var loadedModel: WhisperModelID?

    /// Interview audio is short English segments already split by the VAD: skip the language
    /// pass, drop timestamp/special tokens from the text, and keep the no-speech gate so silence
    /// does not become hallucinated filler.
    private static let options = DecodingOptions(
        task: .transcribe,
        language: "en",
        skipSpecialTokens: true,
        withoutTimestamps: true,
        noSpeechThreshold: 0.6
    )

    func prepare(model: WhisperModelID, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if loadedModel == model, kit != nil {
            onProgress(1)
            return
        }
        onProgress(0.05)
        let started = Date()
        let config = WhisperKitConfig(model: model.whisperKitName, verbose: false, logLevel: .error)
        do {
            kit = try await WhisperKit(config)
        } catch {
            ListenLog.whisper.error("model load failed for \(model.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ChatError.transport("Whisper model \(model.label) could not be loaded: \(error.localizedDescription)")
        }
        loadedModel = model
        ListenLog.whisper.info("model \(model.rawValue, privacy: .public) ready in \(Int(Date().timeIntervalSince(started)))s")
        onProgress(1)
    }

    func transcribe(pcm: [Float], sampleRate: Int) async throws -> String {
        guard let kit else {
            throw ChatError.transport("Whisper model is not ready.")
        }
        let resampled = AudioResampler.downsample(pcm, from: sampleRate, to: 16_000)
        let started = Date()
        let results = try await kit.transcribe(audioArray: resampled, decodeOptions: Self.options)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ListenLog.whisper.info("transcribed \(resampled.count / 16_000)s in \(Int(Date().timeIntervalSince(started) * 1000))ms: \(text.count) chars")
        return text
    }
}
