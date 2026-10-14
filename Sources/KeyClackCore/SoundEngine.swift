import AVFoundation
import Foundation

/// Low-latency, polyphonic playback of pre-decoded buffers.
///
/// A fixed pool of player nodes ("voices") feeds the main mixer; each keystroke takes the next
/// voice round-robin, so fast typing overlaps naturally instead of cutting sounds off. A held
/// key's auto-repeats retrigger *the same* voice, so a long sound (faaa) restarts — "fa-fa-fa" —
/// instead of stacking dozens of copies on top of each other.
///
/// Not thread-safe: call it from one thread (the app uses the main thread throughout).
public final class SoundEngine {
    public static let voiceCount = 24

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var voiceForKey: [Int: Int] = [:]
    private let builtins: [BuiltinSound: [AVAudioPCMBuffer]]
    /// Whether the owner wants audio running; used to recover after device changes.
    private var wantsRunning = false
    private var configObserver: NSObjectProtocol?

    public init() {
        builtins = Dictionary(uniqueKeysWithValues: BuiltinSound.allCases.map { ($0, SoundSynth.variants(of: $0)) })
        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: SoundSynth.format)
            voices.append(node)
        }
        // Headphones plugged in, AirPods connected, etc. stop the engine; bring it back.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.wantsRunning else { return }
            try? self.startEngine()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    public var isRunning: Bool { engine.isRunning }

    /// 0...1
    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    public func start() throws {
        wantsRunning = true
        try startEngine()
    }

    /// Releases the audio device (no idle CPU or battery cost while KeyClack is off).
    public func stop() {
        wantsRunning = false
        voices.forEach { $0.stop() }
        engine.stop()
        voiceForKey.removeAll()
    }

    private func startEngine() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    /// Plays a random variant of a built-in sound, with slight level variation.
    public func play(_ sound: BuiltinSound, key: Int? = nil, retrigger: Bool = false) {
        guard let buffer = builtins[sound]?.randomElement() else { return }
        play(buffer, key: key, retrigger: retrigger, gain: Float.random(in: 0.85...1))
    }

    /// - Parameters:
    ///   - key: Associates the voice with this key so a later `retrigger` reuses it.
    ///   - retrigger: Restart the sound on the key's previous voice instead of taking a new one.
    public func play(_ buffer: AVAudioPCMBuffer, key: Int? = nil, retrigger: Bool = false, gain: Float = 1) {
        guard engine.isRunning else { return }
        let index: Int
        if retrigger, let key, let previous = voiceForKey[key] {
            index = previous
        } else {
            index = nextVoice
            nextVoice = (nextVoice + 1) % voices.count
        }
        if let key { voiceForKey[key] = index }
        let node = voices[index]
        node.volume = gain
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }
}
