import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import Cue

struct AudioCaptureTests {
    /// Builds a CMSampleBuffer the way ScreenCaptureKit does: one block buffer of raw PCM plus an audio format description.
    private func sampleBuffer(bytes: [UInt8], asbd: AudioStreamBasicDescription, frames: Int) throws -> CMSampleBuffer {
        var description = asbd
        var format: CMAudioFormatDescription?
        try #require(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        ) == noErr)
        var block: CMBlockBuffer?
        try #require(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ) == noErr)
        let blockBuffer = try #require(block)
        try bytes.withUnsafeBytes { raw in
            try #require(CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytes.count) == noErr)
        }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        try #require(CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        ) == noErr)
        return try #require(sample)
    }

    @Test func decodesMonoFloat32() throws {
        let samples: [Float] = [0.5, -0.25, 0.125, 1.0]
        let bytes = samples.withUnsafeBytes { Array($0) }
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        let buffer = try sampleBuffer(bytes: bytes, asbd: asbd, frames: samples.count)
        let decoded = try #require(SystemAudioCapture.monoPCM(from: buffer))
        #expect(decoded.1 == 48_000)
        #expect(decoded.0 == samples)
    }

    @Test func mixesInterleavedStereoInt16ToMono() throws {
        // Frames: (L, R) = (max, 0), (0, max), (-max, -max)
        let samples: [Int16] = [Int16.max, 0, 0, Int16.max, -Int16.max, -Int16.max]
        let bytes = samples.withUnsafeBytes { Array($0) }
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )
        let buffer = try sampleBuffer(bytes: bytes, asbd: asbd, frames: 3)
        let decoded = try #require(SystemAudioCapture.monoPCM(from: buffer))
        #expect(decoded.1 == 44_100)
        #expect(decoded.0.count == 3)
        #expect(abs(decoded.0[0] - 0.5) < 0.001)
        #expect(abs(decoded.0[1] - 0.5) < 0.001)
        #expect(abs(decoded.0[2] + 1.0) < 0.001)
    }

    @Test func rejectsNonPCM() throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0
        )
        let buffer = try sampleBuffer(bytes: [0, 0, 0, 0], asbd: asbd, frames: 1)
        #expect(SystemAudioCapture.monoPCM(from: buffer) == nil)
    }

    @Test func vadDetectsSpeechFromLoopbackLevels() {
        // Typical SCK loopback speech sits around 0.02–0.1 RMS; silence well under 0.003.
        var vad = EnergyVAD()
        let rate = 16_000
        let silence = [Float](repeating: 0, count: rate / 2)
        let speech = (0..<rate).map { Float(sin(Double($0) * 0.3)) * 0.05 }
        var events = vad.push(silence, chunkStartAbsolute: 0)
        events += vad.push(speech, chunkStartAbsolute: silence.count)
        events += vad.push(silence, chunkStartAbsolute: silence.count + speech.count)
        #expect(events.contains { if case .speechStart = $0 { return true } else { return false } })
        #expect(events.contains { if case .speechEnd = $0 { return true } else { return false } })
    }
}
