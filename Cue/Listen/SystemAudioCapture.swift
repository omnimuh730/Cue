import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

protocol SystemAudioCapturing: AnyObject {
    func start(_ handler: @escaping @Sendable ([Float], Int) -> Void) async throws
    func stop()
}

nonisolated enum ListenLog {
    static let capture = Logger(subsystem: "app.cue", category: "listen.capture")
    static let controller = Logger(subsystem: "app.cue", category: "listen")
    static let whisper = Logger(subsystem: "app.cue", category: "listen.whisper")
}

/// ScreenCaptureKit loopback of the default output device. Audio-only: no `.screen` output is
/// added, which on macOS 15+ maps to the "System Audio Recording Only" permission and needs
/// `NSAudioCaptureUsageDescription` in Info.plist or the stream silently delivers nothing.
final class SystemAudioCapture: NSObject, SystemAudioCapturing, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var handler: (@Sendable ([Float], Int) -> Void)?
    private let queue = DispatchQueue(label: "app.cue.system-audio")
    private var buffersSeen = 0
    private var loggedFormat = false
    /// Called on an arbitrary queue when the stream ends on its own (permission revoked, display change).
    var onStop: (@Sendable (Error?) -> Void)?

    func start(_ handler: @escaping @Sendable ([Float], Int) -> Void) async throws {
        stop()
        self.handler = handler
        buffersSeen = 0
        loggedFormat = false
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            ListenLog.capture.error("shareable content failed: \(error.localizedDescription, privacy: .public)")
            throw ChatError.transport("Screen & System Audio Recording is not allowed for Cue. Enable it in System Settings → Privacy & Security, then try again. (\(error.localizedDescription))")
        }
        guard let display = content.displays.first else {
            throw ChatError.transport("No display available for system audio.")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        do {
            try await stream.startCapture()
        } catch {
            ListenLog.capture.error("startCapture failed: \(error.localizedDescription, privacy: .public)")
            throw ChatError.transport("Could not start system audio capture: \(error.localizedDescription)")
        }
        self.stream = stream
        ListenLog.capture.info("system audio capture started")
    }

    func stop() {
        let current = stream
        stream = nil
        handler = nil
        guard let current else { return }
        ListenLog.capture.info("system audio capture stopped after \(self.buffersSeen) buffers")
        Task {
            try? await current.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let handler else { return }
        guard let (pcm, rate) = Self.monoPCM(from: sampleBuffer) else {
            if !loggedFormat {
                loggedFormat = true
                ListenLog.capture.error("unsupported audio sample buffer format")
            }
            return
        }
        buffersSeen += 1
        if !loggedFormat {
            loggedFormat = true
            ListenLog.capture.info("first audio buffer: \(pcm.count) samples @ \(rate) Hz")
        }
        handler(pcm, rate)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        ListenLog.capture.error("stream stopped: \(error.localizedDescription, privacy: .public)")
        self.stream = nil
        handler = nil
        onStop?(error)
    }

    /// Decodes any linear-PCM layout SCK hands out (float or 16/32-bit int, interleaved or planar,
    /// any channel count) into mono Float samples, reading through the AudioBufferList so
    /// non-contiguous block buffers are handled correctly.
    nonisolated static func monoPCM(from buffer: CMSampleBuffer) -> ([Float], Int)? {
        guard let format = buffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM
        else { return nil }

        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard listSize > 0 else { return nil }

        let listPointer = UnsafeMutableRawPointer.allocate(byteCount: max(listSize, MemoryLayout<AudioBufferList>.size), alignment: 16)
        defer { listPointer.deallocate() }
        let list = listPointer.assumingMemoryBound(to: AudioBufferList.self)
        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: listSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ) == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let bits = Int(asbd.mBitsPerChannel)
        let frames = CMSampleBufferGetNumSamples(buffer)
        guard frames > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channels)

        func accumulate(_ data: UnsafeMutableRawPointer, byteCount: Int, stride: Int, offset: Int) {
            // `stride`/`offset` are in samples: interleaved streams pack channels per frame.
            if isFloat, bits == 32 {
                let samples = data.assumingMemoryBound(to: Float.self)
                let available = byteCount / 4
                for frame in 0..<frames {
                    let index = frame * stride + offset
                    if index < available { mono[frame] += samples[index] * scale }
                }
            } else if !isFloat, bits == 16 {
                let samples = data.assumingMemoryBound(to: Int16.self)
                let available = byteCount / 2
                for frame in 0..<frames {
                    let index = frame * stride + offset
                    if index < available { mono[frame] += Float(samples[index]) / Float(Int16.max) * scale }
                }
            } else if !isFloat, bits == 32 {
                let samples = data.assumingMemoryBound(to: Int32.self)
                let available = byteCount / 4
                for frame in 0..<frames {
                    let index = frame * stride + offset
                    if index < available { mono[frame] += Float(samples[index]) / Float(Int32.max) * scale }
                }
            }
        }

        if isInterleaved {
            guard let first = buffers.first, let data = first.mData else { return nil }
            for channel in 0..<channels {
                accumulate(data, byteCount: Int(first.mDataByteSize), stride: channels, offset: channel)
            }
        } else {
            for channel in 0..<min(channels, buffers.count) {
                guard let data = buffers[channel].mData else { continue }
                accumulate(data, byteCount: Int(buffers[channel].mDataByteSize), stride: 1, offset: 0)
            }
        }
        return (mono, Int(asbd.mSampleRate))
    }
}
