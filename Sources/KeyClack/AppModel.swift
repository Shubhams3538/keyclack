import AppKit
import AVFoundation
import KeyClackCore
import ServiceManagement
import UniformTypeIdentifiers

/// Which half of a keystroke a custom sound is for.
enum SoundSlot {
    case down, up
}

/// An installed Mechvibes pack, as listed in the sound picker.
struct PackInfo: Identifiable, Hashable {
    let folder: String
    let name: String
    var id: String { folder }
}

/// Owns the config and wires the key monitor to the sound engine. Everything runs on the main
/// thread: the event tap is scheduled on the main run loop, so key events arrive here directly.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet { configDidChange(from: oldValue) }
    }
    @Published private(set) var hasPermission = false
    @Published private(set) var isListening = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    /// Stored file names that are referenced by the config but failed to load.
    @Published private(set) var brokenSounds: Set<String> = []
    @Published private(set) var packs: [PackInfo] = []

    let store: ConfigStore
    private let engine = SoundEngine()
    private let monitor = KeyMonitor()
    private var customBuffers: [String: AVAudioPCMBuffer] = [:]
    /// The selected Mechvibes pack, decoded; nil = built-in synthesized sounds.
    private var pack: MechvibesPack?
    private var permissionTimer: Timer?

    init(store: ConfigStore = .standard()) {
        self.store = store
        config = store.load()
        engine.volume = Float(config.effectiveVolume)
        monitor.onKey = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        reloadCustomSounds()
        refreshPacks()
        loadSelectedPack()
        refreshLaunchAtLogin()
        applyEnabled()
    }

    // MARK: - Key handling

    private func handle(_ event: KeyMonitor.Event) {
        guard config.enabled else { return }
        if event.isRepeat && !config.soundOnRepeat { return }
        playSound(for: event)
    }

    private func playSound(for event: KeyMonitor.Event) {
        // Priority: the key's own custom file → "All other keys" file → sound pack → built-in.
        let code = event.keyCode
        let custom = config.customFile(for: code, down: event.isDown).flatMap { customBuffers[$0] }
        let large = KeyCode.isLarge(code)

        if event.isDown {
            if let custom {
                engine.play(custom, key: code, retrigger: event.isRepeat)
            } else if let sound = pack?.pressSound(for: code) {
                engine.play(sound, key: code, retrigger: event.isRepeat, gain: Float.random(in: 0.9...1))
            } else if code == KeyCode.backspace {
                engine.play(.backspacePlaceholder, key: code, retrigger: event.isRepeat)
            } else {
                engine.play(large ? .largePress : .press, key: code, retrigger: event.isRepeat)
            }
        } else {
            if let custom {
                engine.play(custom)
            } else if !config.releaseClicks {
                return
            } else if let pack {
                // Packs without release recordings stay silent on key-up rather than mixing in
                // the synthesized click.
                if let sound = pack.releaseSound(for: code) { engine.play(sound) }
            } else {
                engine.play(large ? .largeRelease : .release)
            }
        }
    }

    /// Plays what pressing the key would play, for the Settings "preview" buttons.
    func preview(keyCode: Int, slot: SoundSlot) {
        if !engine.isRunning { try? engine.start() }
        playSound(for: KeyMonitor.Event(keyCode: keyCode, isDown: slot == .down, isRepeat: false))
        // Don't leave the audio device open if KeyClack is switched off.
        if !config.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + AudioLoader.maxSeconds) { [weak self] in
                guard let self, !self.config.enabled else { return }
                self.engine.stop()
            }
        }
    }

    // MARK: - Config changes

    private func configDidChange(from old: AppConfig) {
        do {
            try store.save(config)
        } catch {
            showError("Couldn't save settings", error)
        }
        if config.effectiveVolume != old.effectiveVolume { engine.volume = Float(config.effectiveVolume) }
        if config.pack != old.pack { loadSelectedPack() }
        // Let the user hear what they just picked.
        if config.pack != old.pack || config.loudness != old.loudness {
            preview(keyCode: 0, slot: .down)
        }
        if config.keySounds != old.keySounds {
            reloadCustomSounds()
            deleteUnreferencedSounds(previously: old.referencedFiles)
        }
        if config.enabled != old.enabled { applyEnabled() }
    }

    private func reloadCustomSounds() {
        var buffers: [String: AVAudioPCMBuffer] = [:]
        var broken = Set<String>()
        for name in config.referencedFiles {
            if let cached = customBuffers[name] {
                buffers[name] = cached
            } else if let buffer = try? AudioLoader.load(store.url(forSound: name)) {
                buffers[name] = buffer
            } else {
                broken.insert(name)
            }
        }
        customBuffers = buffers
        brokenSounds = broken
    }

    /// Imported copies belong to the app; remove them once no key uses them.
    private func deleteUnreferencedSounds(previously: Set<String>) {
        for name in previously.subtracting(config.referencedFiles) {
            store.deleteSound(named: name)
        }
    }

    // MARK: - Sound packs

    func refreshPacks() {
        packs = store.installedPacks().map { PackInfo(folder: $0.folder, name: $0.name) }
    }

    private func loadSelectedPack() {
        guard let folder = config.pack else {
            pack = nil
            return
        }
        do {
            pack = try MechvibesPack.load(from: store.packURL(folder: folder))
        } catch {
            pack = nil
            showError("Couldn't load the sound pack “\(folder)”", error)
            config.pack = nil // falls back to the built-in sound
        }
    }

    /// Asks for a Mechvibes pack (a folder or a .zip), installs it and switches to it.
    func addPack() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a Mechvibes sound pack (folder or .zip)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let folder = try store.importPack(from: url)
            refreshPacks()
            config.pack = folder
        } catch {
            showError("Couldn't add “\(url.lastPathComponent)”", error)
        }
    }

    func revealPacksFolder() {
        try? FileManager.default.createDirectory(at: store.packsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.packsURL)
    }

    // MARK: - Editing key sounds

    /// "All other keys" first, then the rest alphabetically.
    var sortedKeySounds: [KeySound] {
        config.keySounds.sorted { a, b in
            if (a.keyCode == KeyCode.allOtherKeys) != (b.keyCode == KeyCode.allOtherKeys) {
                return a.keyCode == KeyCode.allOtherKeys
            }
            return KeyCode.name(for: a.keyCode).localizedStandardCompare(KeyCode.name(for: b.keyCode)) == .orderedAscending
        }
    }

    func addKey(_ keyCode: Int) {
        guard config.keySound(for: keyCode) == nil else { return }
        config.keySounds.append(KeySound(keyCode: keyCode))
    }

    func removeKey(_ keyCode: Int) {
        config.keySounds.removeAll { $0.keyCode == keyCode }
    }

    func clearSound(keyCode: Int, slot: SoundSlot) {
        setSound(nil, keyCode: keyCode, slot: slot)
    }

    /// Asks for an audio file, validates it decodes, copies it in and assigns it.
    func chooseSound(keyCode: Int, slot: SoundSlot) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a sound for \(KeyCode.name(for: keyCode))"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let buffer = try AudioLoader.load(url)
            let name = try store.importSound(from: url)
            customBuffers[name] = buffer // so reload doesn't decode it twice
            if config.keySound(for: keyCode) == nil { config.keySounds.append(KeySound(keyCode: keyCode)) }
            setSound(name, keyCode: keyCode, slot: slot)
        } catch {
            showError("Couldn't use “\(url.lastPathComponent)”", error)
        }
    }

    private func setSound(_ name: String?, keyCode: Int, slot: SoundSlot) {
        guard let index = config.keySounds.firstIndex(where: { $0.keyCode == keyCode }) else { return }
        switch slot {
        case .down: config.keySounds[index].down = name
        case .up: config.keySounds[index].up = name
        }
    }

    // MARK: - Enabled / permission

    private func applyEnabled() {
        if config.enabled {
            do {
                try engine.start()
            } catch {
                showError("Couldn't start audio output", error)
            }
            startListening()
        } else {
            permissionTimer?.invalidate()
            permissionTimer = nil
            monitor.stop()
            isListening = false
            engine.stop()
        }
    }

    private func startListening() {
        hasPermission = CGPreflightListenEventAccess()
        if !hasPermission {
            // Shows the system prompt once; afterwards the user has to flip the switch in
            // System Settings, so poll until they do.
            CGRequestListenEventAccess()
        }
        isListening = monitor.start()
        if isListening {
            hasPermission = true
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.config.enabled else { return }
                    self.hasPermission = CGPreflightListenEventAccess()
                    if self.hasPermission { self.startListening() }
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Some macOS versions only honour a newly granted permission after the app restarts.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Launch at login

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showError(on ? "Couldn't turn on Launch at Login" : "Couldn't turn off Launch at Login", error)
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Misc

    func revealSoundsFolder() {
        try? FileManager.default.createDirectory(at: store.soundsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.soundsURL)
    }

    private func showError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
