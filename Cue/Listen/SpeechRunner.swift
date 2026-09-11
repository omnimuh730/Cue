import AVFoundation
import Foundation
import Speech

nonisolated final class SpeechRunner: SpeechTranscribing, @unchecked Sendable {
    private let recognitionLock = NSLock()
    private var recognitionTask: SFSpeechRecognitionTask?

    func prepare(model: WhisperModelID, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let status = await requestSpeechAuthorization()
        guard status == .authorized else {
            throw ChatError.transport("Enable Speech Recognition for Cue in System Settings.")
        }
        if #available(macOS 26.0, *) {
            try await ensureAnalyzerAssets { progress in
                onProgress(min(0.95, progress))
            }
        }
        onProgress(1)
    }

    func transcribe(pcm: [Float], sampleRate: Int) async throws -> String {
        if #available(macOS 26.0, *) {
            do {
                return try await transcribeWithAnalyzer(pcm: pcm, sampleRate: sampleRate)
            } catch {
                return try await transcribeWithRecognizer(pcm: pcm, sampleRate: sampleRate)
            }
        }
        return try await transcribeWithRecognizer(pcm: pcm, sampleRate: sampleRate)
    }

    @available(macOS 26.0, *)
    private func ensureAnalyzerAssets(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { return }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
            ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .unsupported:
            return
        case .installed:
            _ = try? await AssetInventory.reserve(locale: locale)
            onProgress(1)
            return
        case .supported, .downloading:
            break
        }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        let progress = request.progress
        let observer = progress.observe(\.fractionCompleted, options: [.new]) { _, _ in
            onProgress(progress.fractionCompleted)
        }
        defer { observer.invalidate() }
        try await request.downloadAndInstall()
        _ = try? await AssetInventory.reserve(locale: locale)
        onProgress(1)
    }

    @available(macOS 26.0, *)
    private func transcribeWithAnalyzer(pcm: [Float], sampleRate: Int) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw ChatError.transport("Apple Speech is not available.")
        }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
            ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let inventory = await AssetInventory.status(forModules: [transcriber])
        guard inventory != .unsupported else {
            throw ChatError.transport("Apple Speech is not available for this language.")
        }
        if inventory != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw ChatError.transport("Apple Speech has no compatible audio format.")
        }
        let buffer = try Self.convert(pcm: pcm, sampleRate: sampleRate, to: analyzerFormat)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let stream = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
        }

        let collection = Task { () -> String in
            var text = ""
            for try await result in transcriber.results {
                text = String(result.text.characters)
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            _ = try await analyzer.analyzeSequence(stream)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
            collection.cancel()
            throw error
        }

        return try await collection.value
    }

    private func transcribeWithRecognizer(pcm: [Float], sampleRate: Int) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.recognizeOnce(pcm: pcm, sampleRate: sampleRate) }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw ChatError.transport("Apple Speech timed out.")
            }
            guard let text = try await group.next() else {
                throw ChatError.transport("Apple Speech produced no text.")
            }
            group.cancelAll()
            cancelRecognition()
            return text
        }
    }

    private func recognizeOnce(pcm: [Float], sampleRate: Int) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw ChatError.transport("Apple Speech is not available.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        guard let format, let buffer = Self.pcmBuffer(pcm: pcm, format: format) else {
            throw ChatError.transport("Could not create audio buffer.")
        }
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            let box = OnceResume(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                box.resume(returning: result.bestTranscription.formattedString)
            }
            recognitionLock.lock()
            recognitionTask = task
            recognitionLock.unlock()
        }
    }

    private func cancelRecognition() {
        recognitionLock.lock()
        let task = recognitionTask
        recognitionTask = nil
        recognitionLock.unlock()
        task?.cancel()
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private static func convert(pcm: [Float], sampleRate: Int, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let source = pcmBuffer(pcm: pcm, format: sourceFormat) else {
            throw ChatError.transport("Could not create audio buffer.")
        }
        if sourceFormat.sampleRate == format.sampleRate,
           sourceFormat.channelCount == format.channelCount,
           sourceFormat.commonFormat == format.commonFormat {
            return source
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
            throw ChatError.transport("Could not convert audio for Apple Speech.")
        }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else {
            throw ChatError.transport("Could not create converted audio buffer.")
        }
        var conversionError: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return source
        }
        if let conversionError {
            throw conversionError
        }
        if status == .error {
            throw ChatError.transport("Could not convert audio for Apple Speech.")
        }
        return output
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

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}
