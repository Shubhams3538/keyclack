import AVFoundation
@testable import KeyClackCore
import XCTest

final class SoundSynthTests: XCTestCase {
    func testEverySoundIsAudibleAndWithinRange() {
        for sound in BuiltinSound.allCases {
            let samples = SoundSynth.samples(for: sound, seed: 1)
            XCTAssertFalse(samples.isEmpty, "\(sound)")
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.3, "\(sound) is too quiet")
            XCTAssertLessThanOrEqual(peak, 1.0, "\(sound) clips")
            XCTAssertFalse(samples.contains { $0.isNaN || $0.isInfinite }, "\(sound)")
        }
    }

    func testSoundsEndSilently() {
        for sound in BuiltinSound.allCases {
            XCTAssertEqual(SoundSynth.samples(for: sound, seed: 3).last ?? 1, 0, accuracy: 1e-4, "\(sound)")
        }
    }

    func testReleaseIsQuieterThanPress() {
        let press = SoundSynth.samples(for: .press, seed: 1).map(abs).max()!
        let release = SoundSynth.samples(for: .release, seed: 1).map(abs).max()!
        XCTAssertLessThan(release, press)
    }

    func testDeterministicPerSeedAndVariesAcrossSeeds() {
        XCTAssertEqual(SoundSynth.samples(for: .press, seed: 5), SoundSynth.samples(for: .press, seed: 5))
        XCTAssertNotEqual(SoundSynth.samples(for: .press, seed: 5), SoundSynth.samples(for: .press, seed: 6))
    }

    func testBuffersAreInEngineFormat() {
        let buffers = SoundSynth.variants(of: .largePress, count: 3)
        XCTAssertEqual(buffers.count, 3)
        for buffer in buffers {
            XCTAssertEqual(buffer.format, SoundSynth.format)
            XCTAssertGreaterThan(buffer.frameLength, 0)
        }
    }
}

final class AudioLoaderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a sine tone WAV in the given format.
    private func writeTone(seconds: Double, sampleRate: Double, channels: AVAudioChannelCount) throws -> URL {
        let url = dir.appendingPathComponent("tone-\(Int(sampleRate))-\(channels).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<Int(channels) {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![c][i] = 0.5 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testMonoFileIsResampledAndDuplicatedToBothChannels() throws {
        let url = try writeTone(seconds: 0.5, sampleRate: 22_050, channels: 1)
        let buffer = try AudioLoader.load(url)
        XCTAssertEqual(buffer.format, SoundSynth.format)
        XCTAssertEqual(Double(buffer.frameLength) / SoundSynth.sampleRate, 0.5, accuracy: 0.02)
        let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
        let mid = Int(buffer.frameLength) / 2
        XCTAssertGreaterThan((0..<100).map { abs(left[mid + $0]) }.max()!, 0.3)
        for i in 0..<Int(buffer.frameLength) { XCTAssertEqual(left[i], right[i]) }
    }

    func testStereoFileAtEngineRateLoads() throws {
        let url = try writeTone(seconds: 0.25, sampleRate: 48_000, channels: 2)
        let buffer = try AudioLoader.load(url)
        XCTAssertEqual(buffer.format, SoundSynth.format)
        XCTAssertEqual(Int(buffer.frameLength), 12_000)
    }

    func testLongFilesAreTrimmed() throws {
        let url = try writeTone(seconds: AudioLoader.maxSeconds + 2, sampleRate: 8_000, channels: 1)
        let buffer = try AudioLoader.load(url)
        XCTAssertEqual(Double(buffer.frameLength) / SoundSynth.sampleRate, AudioLoader.maxSeconds, accuracy: 0.1)
    }

    func testNonAudioFileThrows() throws {
        let url = dir.appendingPathComponent("not-audio.mp3")
        try Data("definitely not audio".utf8).write(to: url)
        XCTAssertThrowsError(try AudioLoader.load(url))
    }
}

final class ConfigTests: XCTestCase {
    private var store: ConfigStore!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ConfigStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    func testDefaultsListBackspaceWithBuiltInSound() {
        let config = store.load()
        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.pack)
        XCTAssertEqual(config.loudness, .quiet)
        XCTAssertEqual(config.keySounds, [KeySound(keyCode: KeyCode.backspace)])
    }

    func testRoundTrip() throws {
        var config = AppConfig()
        config.volume = 0.3
        config.releaseClicks = false
        config.pack = "holy-pandas"
        config.loudness = .medium
        config.keySounds = [KeySound(keyCode: 51, down: "faaa.mp3"), KeySound(keyCode: 49, up: "boing.wav")]
        try store.save(config)
        XCTAssertEqual(store.load(), config)
        XCTAssertEqual(config.referencedFiles, ["faaa.mp3", "boing.wav"])
    }

    func testPartialConfigFillsDefaultsAndClampsAndDedupes() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let json = #"{"volume": 4, "keySounds": [{"keyCode": 1, "down": "a.wav"}, {"keyCode": 1, "down": "b.wav"}]}"#
        try Data(json.utf8).write(to: store.configURL)
        let config = store.load()
        XCTAssertEqual(config.volume, 1)
        XCTAssertTrue(config.soundOnRepeat)
        XCTAssertEqual(config.keySounds, [KeySound(keyCode: 1, down: "a.wav")])
    }

    func testOldConfigWithRemovedFieldsStillLoads() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"soundStyle": "clicky", "loudness": "loud", "volume": 0.2}"#.utf8).write(to: store.configURL)
        let config = store.load()
        XCTAssertEqual(config.volume, 0.2)
        XCTAssertEqual(config.loudness, .quiet)
        XCTAssertNil(config.pack)
    }

    func testCustomFilePriority() {
        var config = AppConfig()
        config.keySounds = [
            KeySound(keyCode: KeyCode.backspace, down: "faaa.mp3"),
            KeySound(keyCode: KeyCode.allOtherKeys, down: "click.wav", up: "clack.wav"),
            KeySound(keyCode: KeyCode.space), // listed, but no files of its own
        ]
        XCTAssertEqual(config.customFile(for: KeyCode.backspace, down: true), "faaa.mp3")
        XCTAssertEqual(config.customFile(for: KeyCode.backspace, down: false), "clack.wav")
        XCTAssertEqual(config.customFile(for: 0, down: true), "click.wav")
        XCTAssertEqual(config.customFile(for: KeyCode.space, down: true), "click.wav")
        config.keySounds.removeAll { $0.keyCode == KeyCode.allOtherKeys }
        XCTAssertNil(config.customFile(for: 0, down: true))
    }

    func testCorruptConfigIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: store.configURL)
        XCTAssertEqual(store.load(), AppConfig())
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("config.corrupt-") })
    }

    func testImportAvoidsNameCollisions() throws {
        let source = store.directory.appendingPathComponent("faaa.mp3")
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source)
        XCTAssertEqual(try store.importSound(from: source), "faaa.mp3")
        XCTAssertEqual(try store.importSound(from: source), "faaa 2.mp3")
    }

    func testSoundURLCannotEscapeSoundsFolder() {
        let url = store.url(forSound: "../../../etc/passwd")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, store.soundsURL.standardizedFileURL)
    }
}

final class MechvibesPackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a 44.1 kHz mono WAV whose sample value encodes which file/section it is.
    @discardableResult
    private func writeWAV(_ path: String, seconds: Double, level: (Double) -> Float) throws -> URL {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = level(Double(i) / 44_100) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func writeConfig(_ json: String) throws {
        try Data(json.utf8).write(to: dir.appendingPathComponent("config.json"))
    }

    private func level(_ buffer: AVAudioPCMBuffer?) -> Float? {
        guard let buffer, buffer.frameLength > 0 else { return nil }
        return buffer.floatChannelData![0][Int(buffer.frameLength) / 2]
    }

    func testKeyCodeTranslation() {
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 30), 0)            // A
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 14), KeyCode.backspace)
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 57), KeyCode.space)
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 28), KeyCode.returnKey)
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 57416), 126)      // Up
        XCTAssertEqual(MechvibesPack.macKeyCode(forMechvibes: 61000), 126)      // Up, other form
        XCTAssertNil(MechvibesPack.macKeyCode(forMechvibes: 9999))
    }

    func testPatternExpansion() throws {
        XCTAssertEqual(try MechvibesPack.expand("press/G_R{0-2}.mp3"), ["press/G_R0.mp3", "press/G_R1.mp3", "press/G_R2.mp3"])
        XCTAssertEqual(try MechvibesPack.expand("sound.ogg"), ["sound.ogg"])
        XCTAssertThrowsError(try MechvibesPack.expand("x{5-1}.mp3"))
    }

    /// Single layout: one recording, keys are [startMs, durationMs] slices of it.
    func testSinglePackSlicesTheRecording() throws {
        // 0–1 s at level 0.1, 1–2 s at 0.2, 2–3 s at 0.3.
        try writeWAV("sound.ogg.wav", seconds: 3) { Float(0.1 * (floor($0) + 1)) }
        try writeConfig(#"""
        {"name": "Test Single", "key_define_type": "single", "sound": "sound.ogg.wav",
         "defines": {"30": [100, 200], "30-up": [1100, 100], "14": [2100, 300], "91": null, "9999": [0, 10]}}
        """#)
        let pack = try MechvibesPack.load(from: dir)
        XCTAssertEqual(pack.name, "Test Single")
        XCTAssertEqual(Double(level(pack.pressSound(for: 0))!), 0.1, accuracy: 0.01)
        XCTAssertEqual(Double(level(pack.releaseSound(for: 0))!), 0.2, accuracy: 0.01)
        XCTAssertEqual(Double(level(pack.pressSound(for: KeyCode.backspace))!), 0.3, accuracy: 0.01)
        let slice = pack.pressSound(for: 0)!
        XCTAssertEqual(Double(slice.frameLength) / SoundSynth.sampleRate, 0.2, accuracy: 0.002)
        // Undefined key falls back to the letter sound.
        XCTAssertEqual(Double(level(pack.pressSound(for: KeyCode.space))!), 0.1, accuracy: 0.01)
        XCTAssertTrue(pack.hasReleaseSounds)
    }

    /// Multi v2 layout: per-key files, a random generic pattern and a generic release.
    func testMultiPackWithGenericPatternAndReleases() throws {
        for i in 0...2 { try writeWAV("press/GENERIC_R\(i).wav", seconds: 0.1) { _ in 0.5 } }
        try writeWAV("press/BACKSPACE.wav", seconds: 0.1) { _ in 0.7 }
        try writeWAV("release/GENERIC.wav", seconds: 0.1) { _ in 0.2 }
        try writeConfig(#"""
        {"name": "Test Multi", "key_define_type": "multi", "version": 2,
         "sound": "press/GENERIC_R{0-2}.wav", "soundup": "release/GENERIC.wav",
         "defines": {"14": "press/BACKSPACE.wav", "28": "press/MISSING.wav", "57": null}}
        """#)
        let pack = try MechvibesPack.load(from: dir)
        XCTAssertEqual(Double(level(pack.pressSound(for: KeyCode.backspace))!), 0.7, accuracy: 0.01)
        XCTAssertEqual(Double(level(pack.pressSound(for: 0))!), 0.5, accuracy: 0.01)
        XCTAssertEqual(Double(level(pack.pressSound(for: KeyCode.returnKey))!), 0.5, accuracy: 0.01)
        XCTAssertEqual(Double(level(pack.releaseSound(for: KeyCode.backspace))!), 0.2, accuracy: 0.01)
    }

    func testPackWithoutReleaseSoundsHasNone() throws {
        try writeWAV("a.wav", seconds: 0.1) { _ in 0.4 }
        try writeConfig(#"{"name": "Old", "key_define_type": "multi", "sound": "sound.ogg", "defines": {"30": "a.wav"}}"#)
        let pack = try MechvibesPack.load(from: dir)
        XCTAssertNil(pack.releaseSound(for: 0))
        XCTAssertFalse(pack.hasReleaseSounds)
        XCTAssertNotNil(pack.pressSound(for: 63)) // fn: not in any pack, still clicks
    }

    func testPathsCannotEscapeThePack() throws {
        let outside = dir.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).wav")
        try writeWAV("../\(outside.lastPathComponent)", seconds: 0.1) { _ in 0.9 }
        defer { try? FileManager.default.removeItem(at: outside) }
        try writeWAV("a.wav", seconds: 0.1) { _ in 0.4 }
        try writeConfig(#"{"key_define_type": "multi", "defines": {"30": "a.wav", "14": "../\#(outside.lastPathComponent)"}}"#)
        let pack = try MechvibesPack.load(from: dir)
        XCTAssertEqual(Double(level(pack.pressSound(for: KeyCode.backspace))!), 0.4, accuracy: 0.01) // fallback, not 0.9
    }

    func testInvalidPacksThrow() throws {
        XCTAssertThrowsError(try MechvibesPack.load(from: dir)) // no config.json
        try writeConfig(#"{"key_define_type": "single", "sound": "nope.ogg", "defines": {}}"#)
        XCTAssertThrowsError(try MechvibesPack.load(from: dir))
        try writeConfig(#"{"key_define_type": "multi", "defines": {"30": "nope.wav"}}"#)
        XCTAssertThrowsError(try MechvibesPack.load(from: dir))
    }

    func testFindsConfigOneLevelDownAndImportsZip() throws {
        let inner = dir.appendingPathComponent("my-pack")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try writeWAV("my-pack/a.wav", seconds: 0.1) { _ in 0.4 }
        try Data(#"{"name": "Zipped", "key_define_type": "multi", "defines": {"30": "a.wav"}}"#.utf8)
            .write(to: inner.appendingPathComponent("config.json"))
        XCTAssertEqual(MechvibesPack.packRoot(in: dir)?.lastPathComponent, "my-pack")

        let zip = dir.appendingPathComponent("my-pack.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", inner.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()

        let store = ConfigStore(directory: dir.appendingPathComponent("store"))
        XCTAssertEqual(try store.importPack(from: zip), "my-pack")
        XCTAssertEqual(try store.importPack(from: zip), "my-pack 2")
        XCTAssertEqual(store.installedPacks().map(\.name), ["Zipped", "Zipped"])
        XCTAssertNoThrow(try MechvibesPack.load(from: store.packURL(folder: "my-pack")))
    }
}

final class KeyNameTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(KeyCode.name(for: KeyCode.backspace), "Backspace")
        XCTAssertEqual(KeyCode.name(for: 0), "A")
        XCTAssertEqual(KeyCode.name(for: 999), "Key 999")
        XCTAssertEqual(KeyCode.name(for: KeyCode.allOtherKeys), "All other keys")
        XCTAssertTrue(KeyCode.isLarge(KeyCode.space))
        XCTAssertFalse(KeyCode.isLarge(0))
    }
}

/// Opt-in check against real packs: `KEYCLACK_PACKS_DIR=<Packs folder> swift test --filter RealPacks`
/// (scripts/get-mechvibes-packs.sh downloads them). Skipped otherwise.
final class RealPacksTests: XCTestCase {
    func testEveryInstalledPackLoads() throws {
        guard let path = ProcessInfo.processInfo.environment["KEYCLACK_PACKS_DIR"] else {
            throw XCTSkip("KEYCLACK_PACKS_DIR not set")
        }
        let folders = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let started = Date()
            let pack = try MechvibesPack.load(from: folder)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            for key in [0, 1, KeyCode.space, KeyCode.backspace, KeyCode.returnKey, 126, 63] {
                let sound = try XCTUnwrap(pack.pressSound(for: key), "\(pack.name) key \(key)")
                let seconds = Double(sound.frameLength) / SoundSynth.sampleRate
                XCTAssertTrue((0.01...1.5).contains(seconds), "\(pack.name) key \(key): \(seconds) s")
                let peak = (0..<Int(sound.frameLength)).map { abs(sound.floatChannelData![0][$0]) }.max() ?? 0
                XCTAssertGreaterThan(peak, 0.01, "\(pack.name) key \(key) is silent")
            }
            print("PACK \(folder.lastPathComponent) “\(pack.name)” load=\(ms)ms releases=\(pack.hasReleaseSounds)")
        }
    }
}
