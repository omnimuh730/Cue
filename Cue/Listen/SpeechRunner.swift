import AVFoundation
import Foundation
import Speech

final class SpeechRunner: SpeechTranscribing, @unchecked Sendable {
    func prepare(model: WhisperModelID, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        onProgress(1)
    }

    func transcribe(pcm: [Float], sampleRate: Int) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await transcribeWithAnalyzer(pcm: pcm, sampleRate: sampleRate)
        }
        return try await transcribeWithRecognizer(pcm: pcm, sampleRate: sampleRate)
    }

    @available(macOS 26.0, *)
    private func transcribeWithAnalyzer(pcm: [Float], sampleRate: Int) async throws -> String {
        let locale = Locale(identifier: "en_US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        guard let format else { throw ChatError.transport("Could not create audio format.") }
        let stream = AsyncStream<AnalyzerInput> { continuation in
            if let buffer = Self.pcmBuffer(pcm: pcm, format: format) {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            continuation.finish()
        }
        try await analyzer.start(inputSequence: stream)
        var text = ""
        for try await result in transcriber.results {
            text = String(result.text.characters)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeWithRecognizer(pcm: [Float], sampleRate: Int) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw ChatError.transport("Apple Speech is not available.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        guard let format, let buffer = Self.pcmBuffer(pcm: pcm, format: format) else {
            throw ChatError.transport("Could not create audio buffer.")
        }
        request.append(buffer)
        request.endAudio()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private static func pcmBuffer(pcm: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(pcm.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        pcm.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: pcm.count)
            }
        }
        return buffer
    }
}
