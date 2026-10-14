import AVFoundation
import Foundation

public enum AudioLoadError: LocalizedError {
    case empty
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "The file contains no audio."
        case .conversionFailed(let reason): "Couldn't convert the audio: \(reason)"
        }
    }
}

/// Decodes an audio file (MP3, WAV, AIFF, M4A, CAF — anything Core Audio reads) into a buffer in
/// `SoundSynth.format`, so it can be played on the same voices as the built-in sounds.
public enum AudioLoader {
    /// Longer files are trimmed: a key sound that plays for minutes is almost certainly a mistake,
    /// and every loaded sound is held fully in memory.
    public static let maxSeconds: Double = 15

    public static func load(_ url: URL, into target: AVAudioFormat = SoundSynth.format,
                            maxSeconds: Double = AudioLoader.maxSeconds) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        let frames = AVAudioFrameCount(min(Double(file.length), maxSeconds * source.sampleRate))
        guard frames > 0,
              let raw = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else {
            throw AudioLoadError.empty
        }
        try file.read(into: raw, frameCount: frames)
        guard raw.frameLength > 0 else { throw AudioLoadError.empty }

        // Convert sample rate (and downmix >2 channels) first, keeping mono as mono: the
        // converter's mono→stereo default is left-channel only, so we duplicate it ourselves.
        let channels: AVAudioChannelCount = source.channelCount == 1 ? 1 : 2
        guard let intermediate = AVAudioFormat(standardFormatWithSampleRate: target.sampleRate, channels: channels) else {
            throw AudioLoadError.conversionFailed("unsupported format")
        }
        let converted = try convert(raw, to: intermediate)
        return channels == target.channelCount ? converted : duplicateMono(converted, into: target)
    }

    private static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if input.format == format { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format) else {
            throw AudioLoadError.conversionFailed("no converter from \(input.format)")
        }
        converter.downmix = true
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioLoadError.conversionFailed("out of memory")
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw AudioLoadError.conversionFailed(error?.localizedDescription ?? "unknown error")
        }
        guard output.frameLength > 0 else { throw AudioLoadError.empty }
        return output
    }

    private static func duplicateMono(_ mono: AVAudioPCMBuffer, into format: AVAudioFormat) -> AVAudioPCMBuffer {
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: mono.frameLength)!
        out.frameLength = mono.frameLength
        let src = mono.floatChannelData![0]
        for channel in 0..<Int(format.channelCount) {
            out.floatChannelData![channel].update(from: src, count: Int(mono.frameLength))
        }
        return out
    }
}
