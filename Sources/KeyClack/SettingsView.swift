import AppKit
import KeyClackCore
import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @EnvironmentObject private var model: AppModel
    @State private var isCapturingKey = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enabled", isOn: $model.config.enabled)
                if model.config.enabled && !model.isListening {
                    PermissionBanner()
                }
                SoundSourcePicker()
                Picker("Loudness", selection: $model.config.loudness) {
                    ForEach(Loudness.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Volume") {
                    Slider(value: $model.config.volume, in: 0...1)
                }
                Toggle("Release sound on key-up", isOn: $model.config.releaseClicks)
                Toggle("Play while a key is held (key-repeat)", isOn: $model.config.soundOnRepeat)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLoginNeedsApproval {
                    Text("Approve KeyClack in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if model.config.keySounds.isEmpty {
                    Text("No custom key sounds. Every key uses the selected sound.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.sortedKeySounds) { keySound in
                    KeySoundRow(keySound: keySound)
                }
                if isCapturingKey {
                    KeyCaptureBox { keyCode in
                        isCapturingKey = false
                        model.addKey(keyCode)
                    } onCancel: {
                        isCapturingKey = false
                    }
                } else {
                    Button {
                        isCapturingKey = true
                    } label: {
                        Label("Add Key…", systemImage: "plus")
                    }
                }
            } header: {
                Text("Custom key sounds")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MP3, WAV, AIFF, M4A, OGG and CAF work. Files are copied into KeyClack's Sounds folder; anything longer than \(Int(AudioLoader.maxSeconds)) s is trimmed. A key's own sound wins over “All other keys”, which wins over the sound pack.")
                    Button("Show Sounds Folder") { model.revealSoundsFolder() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 460)
        .onAppear {
            model.refreshLaunchAtLogin()
            model.refreshPacks()
        }
    }
}

private struct KeySoundRow: View {
    @EnvironmentObject private var model: AppModel
    let keySound: KeySound

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(KeyCode.name(for: keySound.keyCode))
                    .font(.body.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    model.removeKey(keySound.keyCode)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this key's custom sounds")
            }
            slotRow("Press", file: keySound.down, slot: .down)
            slotRow("Release", file: keySound.up, slot: .up)
        }
        .padding(.vertical, 2)
    }

    private func slotRow(_ title: String, file: String?, slot: SoundSlot) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            if let file {
                let broken = model.brokenSounds.contains(file)
                Label(file, systemImage: broken ? "exclamationmark.triangle.fill" : "waveform")
                    .foregroundStyle(broken ? .orange : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(broken ? "This file is missing or can't be decoded; the built-in sound plays instead." : file)
            } else {
                Text("Built-in").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.preview(keyCode: keySound.keyCode, slot: slot)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Preview")
            Button("Choose…") { model.chooseSound(keyCode: keySound.keyCode, slot: slot) }
            if file != nil {
                Button {
                    model.clearSound(keyCode: keySound.keyCode, slot: slot)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Back to built-in")
            }
        }
        .controlSize(.small)
    }
}
