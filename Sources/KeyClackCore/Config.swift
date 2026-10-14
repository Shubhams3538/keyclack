import Foundation

/// Custom sounds for one physical key. `nil` means "use the built-in sound".
public struct KeySound: Codable, Equatable, Identifiable, Sendable {
    public var keyCode: Int
    /// File name inside the store's Sounds folder, played on key-down (and on key-repeat).
    public var down: String?
    /// File name played on key-up.
    public var up: String?

    public var id: Int { keyCode }

    public init(keyCode: Int, down: String? = nil, up: String? = nil) {
        self.keyCode = keyCode
        self.down = down
        self.up = up
    }
}

/// Overall level preset; the volume slider fine-tunes within it.
public enum Loudness: String, Codable, CaseIterable, Identifiable, Sendable {
    case quiet, medium

    public var id: String { rawValue }
    public var displayName: String { self == .quiet ? "Quiet" : "Medium" }
    /// Master gain the preset applies on top of the volume slider.
    public var gain: Double { self == .quiet ? 0.4 : 0.85 }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var enabled = true
    /// 0...1, multiplied by `loudness.gain`.
    public var volume: Double = 0.8
    public var loudness: Loudness = .quiet
    /// Folder name of the Mechvibes pack in the store's Packs folder; nil = built-in synth.
    public var pack: String?
    /// Built-in release click on key-up. Custom key-up sounds play regardless.
    public var releaseClicks = true
    /// Play again on every auto-repeat while a key is held.
    public var soundOnRepeat = true
    /// Backspace is listed by default so its row is there to pick the faaa file.
    public var keySounds: [KeySound] = [KeySound(keyCode: KeyCode.backspace)]

    public init() {}

    /// What the engine's master volume should be.
    public var effectiveVolume: Double { volume * loudness.gain }

    public func keySound(for keyCode: Int) -> KeySound? {
        keySounds.first { $0.keyCode == keyCode }
    }

    /// The custom file for this key and half of the keystroke: the key's own entry first,
    /// then the "All other keys" entry.
    public func customFile(for keyCode: Int, down: Bool) -> String? {
        let own = keySound(for: keyCode).flatMap { down ? $0.down : $0.up }
        return own ?? keySound(for: KeyCode.allOtherKeys).flatMap { down ? $0.down : $0.up }
    }

    /// Every file name the config refers to.
    public var referencedFiles: Set<String> {
        Set(keySounds.flatMap { [$0.down, $0.up] }.compactMap { $0 })
    }

    // Tolerate missing keys so configs written by older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        volume = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .volume) ?? defaults.volume))
        loudness = (try? c.decodeIfPresent(Loudness.self, forKey: .loudness)) ?? defaults.loudness
        pack = try? c.decodeIfPresent(String.self, forKey: .pack)
        releaseClicks = try c.decodeIfPresent(Bool.self, forKey: .releaseClicks) ?? defaults.releaseClicks
        soundOnRepeat = try c.decodeIfPresent(Bool.self, forKey: .soundOnRepeat) ?? defaults.soundOnRepeat
        let sounds = try c.decodeIfPresent([KeySound].self, forKey: .keySounds) ?? defaults.keySounds
        // Drop duplicate key codes from a hand-edited file; first one wins.
        var seen = Set<Int>()
        keySounds = sounds.filter { seen.insert($0.keyCode).inserted }
    }
}

/// Reads/writes `config.json` and owns the folder imported sound files are copied into:
/// `~/Library/Application Support/KeyClack/{config.json,Sounds/}`.
/// Files are copied so a mapping keeps working if the original is moved or deleted.
public struct ConfigStore: Sendable {
    public let directory: URL
    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var soundsURL: URL { directory.appendingPathComponent("Sounds", isDirectory: true) }
    /// Each sub-folder is one Mechvibes pack.
    public var packsURL: URL { directory.appendingPathComponent("Packs", isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> ConfigStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigStore(directory: base.appendingPathComponent("KeyClack", isDirectory: true))
    }

    /// Never throws: a missing file gives defaults; an unreadable one is moved aside (so the
    /// user's mappings aren't silently overwritten) and defaults are used.
    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let backup = directory.appendingPathComponent("config.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: configURL, to: backup)
            return AppConfig()
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    /// Copies `source` into the Sounds folder and returns the stored file name.
    public func importSound(from source: URL) throws -> String {
        try FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        let original = source.lastPathComponent
        var name = original
        var n = 2
        while FileManager.default.fileExists(atPath: soundsURL.appendingPathComponent(name).path) {
            let base = (original as NSString).deletingPathExtension
            let ext = (original as NSString).pathExtension
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: soundsURL.appendingPathComponent(name))
        return name
    }

    /// Resolves a stored name to a URL. Only the last path component is used, so a hand-edited
    /// config can't point outside the Sounds folder.
    public func url(forSound name: String) -> URL {
        soundsURL.appendingPathComponent((name as NSString).lastPathComponent)
    }

    /// Installed packs as (folder name, display name), sorted by display name.
    public func installedPacks() -> [(folder: String, name: String)] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: packsURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return folders
            .compactMap { url in MechvibesPack.displayName(of: url).map { (url.lastPathComponent, $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func packURL(folder: String) -> URL {
        packsURL.appendingPathComponent((folder as NSString).lastPathComponent, isDirectory: true)
    }

    /// Copies a pack folder (or unzips a pack .zip) into the Packs folder; returns the folder name.
    public func importPack(from source: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: packsURL, withIntermediateDirectories: true)
        let staging = fm.temporaryDirectory.appendingPathComponent("KeyClack-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }

        let unpacked: URL
        if source.pathExtension.lowercased() == "zip" {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", source.path, staging.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
            unpacked = staging
        } else {
            unpacked = source
        }
        guard let root = MechvibesPack.packRoot(in: unpacked) else { throw PackLoadError.missingConfig }
        _ = try MechvibesPack.load(from: root) // validate before installing

        // A zip with config.json at its top level has no folder name of its own: use the zip's.
        let unpackedAtTop = root.resolvingSymlinksInPath().path == staging.resolvingSymlinksInPath().path
        let base = unpackedAtTop ? source.deletingPathExtension().lastPathComponent : root.lastPathComponent
        var folder = base, n = 2
        while fm.fileExists(atPath: packsURL.appendingPathComponent(folder).path) {
            folder = "\(base) \(n)"
            n += 1
        }
        try fm.copyItem(at: root, to: packsURL.appendingPathComponent(folder))
        return folder
    }

    public func deleteSound(named name: String) {
        try? FileManager.default.removeItem(at: url(forSound: name))
    }
}
