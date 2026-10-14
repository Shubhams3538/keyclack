import AVFoundation
import Foundation

/// The sounds KeyClack generates itself, so the app works (and the repo stays free of
/// third-party recordings) before the user picks any files or sound packs.
public enum BuiltinSound: CaseIterable, Sendable {
    case press, release, largePress, largeRelease
    /// Default backspace sound until the user picks their own (the "faaa" clip).
    case backspacePlaceholder
}

/// Procedural mechanical-keyboard sounds.
///
/// A keystroke is modelled as three layered events:
/// 1. a short high-passed noise *tick* (switch contact / stem hitting the housing),
/// 2. a low-passed noise *thud* a few ms later (keycap bottoming out on the plate),
/// 3. a damped two-partial sine *body* resonance excited by the thud (case/plate ring).
/// Long keys add a second, quieter thud: the stabiliser rattle.
///
/// For a properly realistic sound, use a recorded Mechvibes pack instead (see `MechvibesPack`).
public enum SoundSynth {
    public static let sampleRate: Double = 48_000

    /// The format every buffer the engine plays is in (built-in, imported and pack sounds alike).
    public static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    /// Several slightly different takes of a sound, so repeated keystrokes don't sound robotic.
    public static func variants(of sound: BuiltinSound, count: Int = 6) -> [AVAudioPCMBuffer] {
        (0..<count).map { makeBuffer(samples(for: sound, seed: UInt64($0) &+ 1)) }
    }

    /// Mono samples in -1...1. Deterministic for a given seed.
    public static func samples(for sound: BuiltinSound, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed &* 0x9E37_79B9 &+ UInt64(sound.hashSalt))
        switch sound {
        case .press:
            return normalized(stroke(.press.jittered(&rng), rng: &rng), peak: 0.8)
        case .release:
            return normalized(stroke(.release.jittered(&rng), rng: &rng), peak: 0.42)
        case .largePress:
            return normalized(stroke(.largePress.jittered(&rng), rng: &rng), peak: 0.9)
        case .largeRelease:
            return normalized(stroke(.largeRelease.jittered(&rng), rng: &rng), peak: 0.48)
        case .backspacePlaceholder:
            return normalized(placeholderBoop(rng: &rng), peak: 0.7)
        }
    }

    public static func makeBuffer(_ mono: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count))!
        buffer.frameLength = AVAudioFrameCount(mono.count)
        for channel in 0..<Int(format.channelCount) {
            let dst = buffer.floatChannelData![channel]
            mono.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!, count: mono.count)
            }
        }
        return buffer
    }

    // MARK: - Keystroke model

    struct StrokeParams {
        var tickAmp: Float
        var tickDecay: Double      // s
        var bottomDelay: Double    // s from tick to thud
        var thudAmp: Float
        var thudDecay: Double      // s
        var thudCutoff: Double     // Hz, one-pole low-pass on the thud noise
        var bodyFreq: Double       // Hz
        var bodyAmp: Float
        var bodyDecay: Double      // s
        var rattleDelay: Double?   // s after the thud; nil = no stabiliser
        var duration: Double       // s

        static let press = StrokeParams(
            tickAmp: 0.6, tickDecay: 0.0008, bottomDelay: 0.006, thudAmp: 1.0, thudDecay: 0.004,
            thudCutoff: 2500, bodyFreq: 260, bodyAmp: 0.5, bodyDecay: 0.018, rattleDelay: nil,
            duration: 0.09)
        static let release = StrokeParams(
            tickAmp: 0.5, tickDecay: 0.0006, bottomDelay: 0.003, thudAmp: 0.45, thudDecay: 0.003,
            thudCutoff: 3500, bodyFreq: 420, bodyAmp: 0.25, bodyDecay: 0.010, rattleDelay: nil,
            duration: 0.06)
        static let largePress = StrokeParams(
            tickAmp: 0.4, tickDecay: 0.0010, bottomDelay: 0.009, thudAmp: 1.0, thudDecay: 0.007,
            thudCutoff: 1500, bodyFreq: 140, bodyAmp: 0.8, bodyDecay: 0.035, rattleDelay: 0.014,
            duration: 0.16)
        static let largeRelease = StrokeParams(
            tickAmp: 0.4, tickDecay: 0.0008, bottomDelay: 0.004, thudAmp: 0.5, thudDecay: 0.004,
            thudCutoff: 2200, bodyFreq: 220, bodyAmp: 0.35, bodyDecay: 0.015, rattleDelay: 0.010,
            duration: 0.09)

        /// Small random variation so each variant is a distinct "take".
        func jittered(_ rng: inout SplitMix64) -> StrokeParams {
            var p = self
            p.bodyFreq *= rng.uniform(0.94, 1.06)
            p.bottomDelay *= rng.uniform(0.8, 1.2)
            p.thudCutoff *= rng.uniform(0.85, 1.15)
            p.tickAmp *= Float(rng.uniform(0.8, 1.2))
            p.bodyDecay *= rng.uniform(0.9, 1.1)
            p.rattleDelay = p.rattleDelay.map { $0 * rng.uniform(0.8, 1.25) }
            return p
        }
    }

    static func stroke(_ p: StrokeParams, rng: inout SplitMix64) -> [Float] {
        var out = [Float](repeating: 0, count: Int(p.duration * sampleRate))
        addTick(&out, at: 0, amp: p.tickAmp, decay: p.tickDecay, rng: &rng)
        addThud(&out, at: p.bottomDelay, amp: p.thudAmp, p: p, rng: &rng)
        if let rattle = p.rattleDelay {
            let t = p.bottomDelay + rattle
            addTick(&out, at: t, amp: p.tickAmp * 0.5, decay: p.tickDecay, rng: &rng)
            addThud(&out, at: t, amp: p.thudAmp * 0.35, p: p, rng: &rng)
        }
        fadeOut(&out, seconds: 0.005)
        return out
    }

    /// High-passed (first-difference) noise burst with an exponential decay.
    private static func addTick(_ out: inout [Float], at start: Double, amp: Float, decay: Double,
                                rng: inout SplitMix64) {
        let first = Int(start * sampleRate)
        var previous: Float = 0
        for i in first..<out.count {
            let env = exp(-Double(i - first) / sampleRate / decay)
            if env < 1e-4 { break }
            let white = rng.signedFloat()
            out[i] += amp * Float(env) * (white - previous)
            previous = white
        }
    }

    /// Low-passed noise burst plus the body resonance it excites.
    private static func addThud(_ out: inout [Float], at start: Double, amp: Float, p: StrokeParams,
                                rng: inout SplitMix64) {
        let first = Int(start * sampleRate)
        guard first < out.count else { return }
        let a = Float(exp(-2 * Double.pi * p.thudCutoff / sampleRate))
        var lowpassed: Float = 0
        for i in first..<out.count {
            let t = Double(i - first) / sampleRate
            lowpassed = (1 - a) * rng.signedFloat() + a * lowpassed
            let noise = Float(exp(-t / p.thudDecay)) * lowpassed * 3 // low-pass loses level; make it up
            let w = 2 * Double.pi * p.bodyFreq * t
            let body = exp(-t / p.bodyDecay) * sin(w)
                + 0.4 * exp(-t / (p.bodyDecay * 0.4)) * sin(w * 2.76) // inharmonic plate partial
            out[i] += amp * (noise + p.bodyAmp * Float(body))
        }
    }

    // MARK: - Backspace placeholder

    /// A short descending cartoon "bwoop": obviously not a keystroke, so it's clear backspace is
    /// waiting for a custom sound. Layered on a normal press so it still feels like a key.
    static func placeholderBoop(rng: inout SplitMix64) -> [Float] {
        let duration = 0.24
        var out = [Float](repeating: 0, count: Int(duration * sampleRate))
        let click = stroke(.largePress.jittered(&rng), rng: &rng)
        let clickPeak = click.map(abs).max() ?? 1
        for i in 0..<min(click.count, out.count) { out[i] += 0.6 * click[i] / clickPeak }

        let f0 = 700.0 * rng.uniform(0.95, 1.05), f1 = 220.0
        var phase = 0.0
        for i in 0..<out.count {
            let t = Double(i) / sampleRate
            let freq = f0 * pow(f1 / f0, t / duration) // exponential sweep
            phase += 2 * Double.pi * freq / sampleRate
            let env = min(1, t / 0.005) * exp(-t / 0.09)
            out[i] += Float(0.8 * env * (sin(phase) + 0.25 * sin(2 * phase)))
        }
        fadeOut(&out, seconds: 0.01)
        return out
    }

    // MARK: - Helpers

    private static func fadeOut(_ out: inout [Float], seconds: Double) {
        let n = min(out.count, Int(seconds * sampleRate))
        guard n > 0 else { return }
        for k in 0..<n { out[out.count - n + k] *= Float(n - 1 - k) / Float(n) }
    }

    static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        let current = samples.map(abs).max() ?? 0
        guard current > 0 else { return samples }
        let gain = peak / current
        return samples.map { $0 * gain }
    }
}

private extension BuiltinSound {
    var hashSalt: Int {
        switch self {
        case .press: 11
        case .release: 23
        case .largePress: 37
        case .largeRelease: 41
        case .backspacePlaceholder: 53
        }
    }
}

/// Tiny deterministic PRNG so built-in sounds are identical on every launch and in tests.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    mutating func signedFloat() -> Float { Float(unit() * 2 - 1) }
}
