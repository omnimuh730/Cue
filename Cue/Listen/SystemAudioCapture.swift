import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

protocol SystemAudioCapturing: AnyObject {
    func start(_ handler: @escaping @Sendable ([Float], Int) -> Void) async throws
    func stop()
}

final class SystemAudioCapture: NSObject, SystemAudioCapturing, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var handler: (@Sendable ([Float], Int) -> Void)?
    private let queue = DispatchQueue(label: "app.cue.system-audio")

    func start(_ handler: @escaping @Sendable ([Float], Int) -> Void) async throws {
        stop()
        self.handler = handler
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        let current = stream
        stream = nil
        handler = nil
        Task {
            try? await current?.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let handler else { return }
        guard let pcm = Self.floatPCM(from: sampleBuffer) else { return }
        let rate = Self.sampleRate(from: sampleBuffer) ?? 48_000
        handler(pcm, rate)
    }

    private static func sampleRate(from buffer: CMSampleBuffer) -> Int? {
        guard let format = buffer.formatDescription else { return nil }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        return asbd.map { Int($0.mSampleRate) }
    }

    private static func floatPCM(from buffer: CMSampleBuffer) -> [Float]? {
        guard let block = buffer.dataBuffer else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let dataPointer, length > 0
        else { return nil }

        if let format = buffer.formatDescription {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            if let asbd, asbd.mFormatID == kAudioFormatLinearPCM {
                if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                    let count = length / MemoryLayout<Float>.size
                    return UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: count).withMemoryRebound(to: Float.self, capacity: count) { ptr in
                        Array(UnsafeBufferPointer(start: ptr, count: count))
                    }
                }
                if asbd.mBitsPerChannel == 16 {
                    let count = length / MemoryLayout<Int16>.size
                    let samples = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: count)
                    return (0..<count).map { Float(samples[$0]) / Float(Int16.max) }
                }
            }
        }
        return nil
    }
}
