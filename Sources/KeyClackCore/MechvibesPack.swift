import AVFoundation
import Foundation

public enum PackLoadError: LocalizedError {
    case missingConfig
    case invalidConfig(String)
    case noSounds

    public var errorDescription: String? {
        switch self {
        case .missingConfig: "This folder isn't a Mechvibes sound pack (no config.json found)."
        case .invalidConfig(let reason): "The pack's config.json is invalid: \(reason)"
        case .noSounds: "The pack doesn't contain any playable sounds."
        }
    }
}

/// A Mechvibes sound pack (https://mechvibes.com): real recordings of mechanical switches.
///
/// A pack is a folder with a `config.json` in one of two layouts:
/// - `"key_define_type": "single"`: one long recording (`"sound"`); each key maps to a
///   `[startMs, durationMs]` slice of it.
/// - `"key_define_type": "multi"`: each key maps to its own file.
///
/// Optional extensions seen in real packs: `"<code>-up"` entries for release sounds, a
/// `"sound"` pattern such as `"press/GENERIC_R{0-4}.mp3"` (random pick for keys without their
/// own entry), and `"soundup"` (generic release). `null` entries mean "no specific sound".
/// Key codes are libuiohook's (PC scan-code based); `macKeyCode(forMechvibes:)` translates them.
public struct MechvibesPack {
    public let name: String
    private let press: [Int: [AVAudioPCMBuffer]]
    private let release: [Int: [AVAudioPCMBuffer]]
    private let genericPress: [AVAudioPCMBuffer]
    private let genericRelease: [AVAudioPCMBuffer]

    /// Recordings in packs are long (the single-file layout is often 30–60 s).
    public static let maxRecordingSeconds: Double = 300

    /// Sound for a key press; falls back to the pack's generic sound for keys it doesn't define.
    public func pressSound(for macKeyCode: Int) -> AVAudioPCMBuffer? {
        press[macKeyCode]?.randomElement() ?? genericPress.randomElement()
    }

    /// Release sound, or nil if the pack has none (most older packs only record presses).
    public func releaseSound(for macKeyCode: Int) -> AVAudioPCMBuffer? {
        release[macKeyCode]?.randomElement() ?? genericRelease.randomElement()
    }

    public var hasReleaseSounds: Bool { !release.isEmpty || !genericRelease.isEmpty }

    /// Finds the folder holding `config.json`: `folder` itself or one level down (a pack zip
    /// usually unpacks to a single sub-folder).
    public static func packRoot(in folder: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("config.json").path) { return folder }
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.first { fm.fileExists(atPath: $0.appendingPathComponent("config.json").path) }
    }

    /// Display name from config.json, without decoding any audio.
    public static func displayName(of folder: URL) -> String? {
        guard let root = packRoot(in: folder),
              let data = try? Data(contentsOf: root.appendingPathComponent("config.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["name"] as? String) ?? folder.lastPathComponent
    }

    public static func load(from folder: URL) throws -> MechvibesPack {
        guard let root = packRoot(in: folder) else { throw PackLoadError.missingConfig }
        let data = try Data(contentsOf: root.appendingPathComponent("config.json"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PackLoadError.invalidConfig("not a JSON object")
        }
        guard let defines = json["defines"] as? [String: Any] else {
            throw PackLoadError.invalidConfig("missing \"defines\"")
        }
        let name = (json["name"] as? String) ?? folder.lastPathComponent
        let type = (json["key_define_type"] as? String) ?? "single"
        var loader = FileCache(root: root)

        var press: [Int: [AVAudioPCMBuffer]] = [:]
        var release: [Int: [AVAudioPCMBuffer]] = [:]
        var genericPress: [AVAudioPCMBuffer] = []
        var genericRelease: [AVAudioPCMBuffer] = []

        if type == "single" {
            guard let soundName = json["sound"] as? String else {
                throw PackLoadError.invalidConfig("a \"single\" pack needs a \"sound\" file")
            }
            let recording = try loader.buffer(soundName, required: true)!
            for (key, value) in defines {
                guard let (code, isUp) = parseKey(key),
                      let range = value as? [Any], range.count == 2,
                      let start = (range[0] as? NSNumber)?.doubleValue,
                      let length = (range[1] as? NSNumber)?.doubleValue,
                      let slice = slice(recording, startMs: start, lengthMs: length) else { continue }
                if isUp { release[code, default: []].append(slice) } else { press[code, default: []].append(slice) }
            }
        } else if type == "multi" {
            for (key, value) in defines {
                guard let (code, isUp) = parseKey(key), let file = value as? String,
                      let buffer = try loader.buffer(file, required: false) else { continue }
                if isUp { release[code, default: []].append(buffer) } else { press[code, default: []].append(buffer) }
            }
            // Generic sounds. Older multi packs list a "sound" that doesn't exist; that's fine.
            if let pattern = json["sound"] as? String {
                genericPress = try expand(pattern).compactMap { try loader.buffer($0, required: false) }
            }
            if let pattern = json["soundup"] as? String {
                genericRelease = try expand(pattern).compactMap { try loader.buffer($0, required: false) }
            }
        } else {
            throw PackLoadError.invalidConfig("unknown key_define_type \"\(type)\"")
        }

        // Keys a pack doesn't define (and Mac-only keys like fn) still need a sound: borrow the
        // letter keys' sounds, which is what most packs record most carefully.
        if genericPress.isEmpty {
            genericPress = [0, 1, 2, 3, 37, 38, 40].compactMap { press[$0]?.first }
            if genericPress.isEmpty, let any = press.values.first?.first { genericPress = [any] }
        }
        guard !genericPress.isEmpty else { throw PackLoadError.noSounds }

        return MechvibesPack(name: name, press: press, release: release,
                             genericPress: genericPress, genericRelease: genericRelease)
    }

    // MARK: - Parsing helpers

    /// "30" → (A, false); "30-up" → (A, true); unknown codes → nil.
    private static func parseKey(_ key: String) -> (Int, Bool)? {
        let isUp = key.hasSuffix("-up")
        let number = isUp ? String(key.dropLast(3)) : key
        guard let code = Int(number), let mac = macKeyCode(forMechvibes: code) else { return nil }
        return (mac, isUp)
    }

    /// "press/GENERIC_R{0-4}.mp3" → ["press/GENERIC_R0.mp3", …, "press/GENERIC_R4.mp3"].
    static func expand(_ pattern: String) throws -> [String] {
        guard let open = pattern.firstIndex(of: "{"), let close = pattern[open...].firstIndex(of: "}") else {
            return [pattern]
        }
        let bounds = pattern[pattern.index(after: open)..<close].split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 100 else {
            throw PackLoadError.invalidConfig("bad sound pattern \"\(pattern)\"")
        }
        let prefix = pattern[..<open], suffix = pattern[pattern.index(after: close)...]
        return (bounds[0]...bounds[1]).map { "\(prefix)\($0)\(suffix)" }
    }

    private static func slice(_ buffer: AVAudioPCMBuffer, startMs: Double, lengthMs: Double) -> AVAudioPCMBuffer? {
        let rate = buffer.format.sampleRate
        let start = Int((startMs / 1000 * rate).rounded())
        let length = min(Int((lengthMs / 1000 * rate).rounded()), Int(buffer.frameLength) - start)
        guard start >= 0, length > 0,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length)) else {
            return nil
        }
        out.frameLength = AVAudioFrameCount(length)
        for channel in 0..<Int(buffer.format.channelCount) {
            out.floatChannelData![channel].update(from: buffer.floatChannelData![channel] + start, count: length)
        }
        // Slices are cut mid-recording; a 2 ms fade avoids a click at the cut.
        let fade = min(length, Int(0.002 * rate))
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = out.floatChannelData![channel]
            for k in 0..<fade { samples[length - 1 - k] *= Float(k) / Float(fade) }
        }
        return out
    }

    /// Decodes each referenced file once, and refuses paths that leave the pack folder.
    private struct FileCache {
        let root: URL
        var cache: [String: AVAudioPCMBuffer] = [:]

        mutating func buffer(_ relativePath: String, required: Bool) throws -> AVAudioPCMBuffer? {
            if let hit = cache[relativePath] { return hit }
            let url = root.appendingPathComponent(relativePath).standardizedFileURL
            let rootPath = root.standardizedFileURL.path + "/"
            guard url.path.hasPrefix(rootPath), FileManager.default.fileExists(atPath: url.path) else {
                if required { throw PackLoadError.invalidConfig("missing file \"\(relativePath)\"") }
                return nil
            }
            do {
                let buffer = try AudioLoader.load(url, maxSeconds: MechvibesPack.maxRecordingSeconds)
                cache[relativePath] = buffer
                return buffer
            } catch {
                if required { throw error }
                return nil
            }
        }
    }

    // MARK: - Key codes

    /// libuiohook virtual key code (what Mechvibes uses) → macOS virtual key code (kVK_*).
    public static func macKeyCode(forMechvibes code: Int) -> Int? { uiohookToMac[code] }

    private static let uiohookToMac: [Int: Int] = [
        1: 53, // Escape
        2: 18, 3: 19, 4: 20, 5: 21, 6: 23, 7: 22, 8: 26, 9: 28, 10: 25, 11: 29, // 1…0
        12: 27, 13: 24, 14: 51, 15: 48, // - = Backspace Tab
        16: 12, 17: 13, 18: 14, 19: 15, 20: 17, 21: 16, 22: 32, 23: 34, 24: 31, 25: 35, // Q…P
        26: 33, 27: 30, 28: 36, 29: 59, // [ ] Return LeftCtrl
        30: 0, 31: 1, 32: 2, 33: 3, 34: 5, 35: 4, 36: 38, 37: 40, 38: 37, // A…L
        39: 41, 40: 39, 41: 50, 42: 56, 43: 42, // ; ' ` LeftShift \
        44: 6, 45: 7, 46: 8, 47: 9, 48: 11, 49: 45, 50: 46, // Z…M
        51: 43, 52: 47, 53: 44, 54: 60, // , . / RightShift
        55: 67, 56: 58, 57: 49, 58: 57, // Keypad* LeftAlt Space CapsLock
        59: 122, 60: 120, 61: 99, 62: 118, 63: 96, 64: 97, 65: 98, 66: 100, 67: 101, 68: 109, // F1…F10
        69: 71, // NumLock → Keypad Clear
        71: 89, 72: 91, 73: 92, 74: 78, 75: 86, 76: 87, 77: 88, 78: 69, // Keypad 7 8 9 - 4 5 6 +
        79: 83, 80: 84, 81: 85, 82: 82, 83: 65, // Keypad 1 2 3 0 .
        87: 103, 88: 111, 91: 105, 92: 107, 93: 113, // F11 F12 F13 F14 F15
        3597: 81, // Keypad =
        3612: 76, 3613: 62, 3637: 75, 3640: 61, // Keypad Enter, RightCtrl, Keypad /, RightAlt
        3655: 115, 3657: 116, 3663: 119, 3665: 121, 3666: 114, 3667: 117, // Home PgUp End PgDn Insert Delete
        3675: 55, 3676: 54, // Left/Right Meta → Command
        57416: 126, 57419: 123, 57421: 124, 57424: 125, // arrows (scan-code form)
        60999: 115, 61000: 126, 61001: 116, 61003: 123, 61005: 124, // Home Up PgUp Left Right
        61007: 119, 61008: 125, 61009: 121, 61010: 114, 61011: 117, // End Down PgDn Insert Delete
    ]
}
