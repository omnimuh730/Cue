import Foundation

@MainActor
@Observable
final class ListenController {
    private let ring = AudioRingBuffer()
    private var vad = EnergyVAD()
    private let audio = SystemAudioCapture()
    private let whisper = WhisperRunner()
    private let speech = SpeechRunner()
    private let captions = LiveCaptionAXClient()
    private var assembler = CaptionLineAssembler()
    private var audioRunning = false
    private var transcribing = false
    private var queue: [(pcm: [Float], endSample: Int)] = []
    private var lastEmittedText = ""
    private var lastStatusEmit = Date.distantPast

    var status = ListenStatus.idle
    var onTranscript: ((String) -> Void)?
    var onStatus: ((ListenStatus) -> Void)?

    func configure(settings: PublicSettings) {
        status.mode = settings.listenMode
        status.model = settings.whisperModel
        status.audioAutoMode = settings.audioAutoMode
        status.accessibilityTrusted = AccessibilityTrust.isTrusted
        status.liveCaptionsRunning = LiveCaptionsProcess.runningApplication() != nil
        emit(force: true)
    }

    func setArmed(_ armed: Bool, settings: PublicSettings) async {
        status.armed = armed
        status.error = nil
        if !armed {
            status.manualActive = false
            vad.reset(absoluteSample: ring.nowSample)
            status.phase = .off
            status.inputLevel = 0
            stopSources()
            emit(force: true)
            return
        }
        await startSources(settings: settings)
    }

    func toggleArmed(settings: PublicSettings) async {
        if status.audioAutoMode {
            await setArmed(!status.armed, settings: settings)
        } else if status.manualActive {
            await manualStop()
        } else {
            await manualStart(settings: settings)
        }
    }

    func listenOff(settings: PublicSettings) async {
        if status.manualActive { await manualStop() }
        if status.armed { await setArmed(false, settings: settings) }
    }

    func manualStart(settings: PublicSettings) async {
        if !status.armed { await setArmed(true, settings: settings) }
        status.manualActive = true
        status.phase = .listening
        emit(force: true)
    }

    func manualStop() async {
        guard status.manualActive else { return }
        let start = ring.watermarkSampleIndex
        let end = ring.nowSample
        status.manualActive = false
        emit(force: true)
        await enqueueSegment(start: start, end: end)
    }

    func resetAfterSend() {
        ring.resetToNow()
        vad.reset(absoluteSample: ring.nowSample)
        queue = []
        lastEmittedText = ""
        assembler.reset()
        status.manualActive = false
        status.phase = status.armed ? .armed : .off
        status.error = nil
        emit(force: true)
    }

    private func startSources(settings: PublicSettings) async {
        status.mode = settings.listenMode
        switch settings.listenMode {
        case .accessibility:
            guard AccessibilityTrust.isTrusted else {
                AccessibilityTrust.request()
                status.error = "Grant Accessibility, then enable Live Captions."
                status.phase = .error
                status.armed = false
                emit(force: true)
                return
            }
            status.phase = .armed
            status.modelReady = true
            captions.onRunningChange = { [weak self] in
                Task { @MainActor in
                    self?.status.liveCaptionsRunning = LiveCaptionsProcess.runningApplication() != nil
                    self?.emit(force: true)
                }
            }
            captions.start { [weak self] text in
                Task { @MainActor in
                    self?.ingestCaptions(text)
                }
            }
            emit(force: true)
        case .whisper, .appleSpeech:
            do {
                status.phase = .downloading
                emit(force: true)
                try await transcriber(for: settings.listenMode).prepare(model: settings.whisperModel) { [weak self] progress in
                    Task { @MainActor in
                        self?.status.downloadProgress = progress
                        self?.emit()
                    }
                }
                status.modelReady = true
                status.downloadProgress = nil
                status.phase = .armed
                if !audioRunning {
                    try await audio.start { [weak self] pcm, rate in
                        Task { @MainActor in
                            self?.pushPcm(pcm, sampleRate: rate)
                        }
                    }
                    audioRunning = true
                }
                emit(force: true)
            } catch {
                status.modelReady = false
                status.error = error.localizedDescription
                status.phase = .error
                status.armed = false
                emit(force: true)
            }
        }
    }

    private func stopSources() {
        captions.stop()
        if audioRunning {
            audio.stop()
            audioRunning = false
        }
    }

    private func transcriber(for mode: ListenMode) -> SpeechTranscribing {
        mode == .whisper ? whisper : speech
    }

    private func ingestCaptions(_ raw: String) {
        guard assembler.ingest(raw) else { return }
        status.phase = .listening
        if let live = assembler.lines.last(where: \.isLive)?.text, live != lastEmittedText {
            lastEmittedText = live
            onTranscript?(live)
        }
        emit(force: true)
    }

    private func pushPcm(_ pcm: [Float], sampleRate: Int) {
        guard status.armed || status.manualActive else { return }
        let peak = pcm.map(abs).max() ?? 0
        status.inputLevel = min(1, Double(peak))
        let resampled = AudioResampler.downsample(pcm, from: sampleRate, to: 16_000)
        let chunkStart = ring.nowSample
        ring.push(resampled)
        if status.manualActive {
            status.phase = .listening
            emit()
            return
        }
        guard status.armed, status.modelReady, status.audioAutoMode else {
            emit()
            return
        }
        let events = vad.push(resampled, chunkStartAbsolute: chunkStart)
        for event in events {
            switch event {
            case .speechStart:
                status.phase = .listening
                emit(force: true)
            case .speechEnd(let start, let end):
                Task { await enqueueSegment(start: max(start, ring.watermarkSampleIndex), end: end) }
            }
        }
        emit()
    }

    private func enqueueSegment(start: Int, end: Int) async {
        guard let pcm = ring.slice(startSample: start, endSample: end), pcm.count >= 16_000 * 2 / 5 else { return }
        if queue.count >= 3 { queue.removeFirst() }
        queue.append((pcm, end))
        await drainQueue()
    }

    private func drainQueue() async {
        if transcribing { return }
        guard let next = queue.first else {
            status.phase = status.armed ? (status.manualActive ? .listening : .armed) : .off
            emit(force: true)
            return
        }
        queue.removeFirst()
        transcribing = true
        status.phase = .transcribing
        emit(force: true)
        do {
            let text = try await transcriber(for: status.mode).transcribe(pcm: next.pcm, sampleRate: 16_000)
            ring.setWatermark(sample: next.endSample)
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, cleaned != lastEmittedText {
                lastEmittedText = cleaned
                onTranscript?(cleaned)
            }
            status.error = nil
        } catch {
            status.error = error.localizedDescription
            status.phase = .error
        }
        transcribing = false
        status.phase = status.armed ? (status.manualActive ? .listening : .armed) : .off
        emit(force: true)
        await drainQueue()
    }

    private func emit(force: Bool = false) {
        let now = Date()
        if !force, now.timeIntervalSince(lastStatusEmit) < 0.12 { return }
        lastStatusEmit = now
        status.accessibilityTrusted = AccessibilityTrust.isTrusted
        onStatus?(status)
    }
}
