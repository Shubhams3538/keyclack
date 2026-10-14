import KeyClackCore
import SwiftUI

@main
struct KeyClackApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.config.enabled ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("KeyClack Settings", id: SettingsView.windowID) {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

/// The popover under the menu-bar icon.
struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isCapturingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KeyClack").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $model.config.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if model.config.enabled && !model.isListening {
                PermissionBanner()
            }

            SoundSourcePicker()

            Picker("Loudness", selection: $model.config.loudness) {
                ForEach(Loudness.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $model.config.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            Toggle("Release sound on key-up", isOn: $model.config.releaseClicks)
            Toggle("Play while a key is held", isOn: $model.config.soundOnRepeat)

            Divider()

            Text("Custom key sounds").font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.sortedKeySounds) { keySound in
                        MenuKeySoundRow(keySound: keySound)
                    }
                }
            }
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)

            if isCapturingKey {
                KeyCaptureBox { keyCode in
                    isCapturingKey = false
                    model.chooseSound(keyCode: keyCode, slot: .down)
                } onCancel: {
                    isCapturingKey = false
                }
            } else {
                Button {
                    isCapturingKey = true
                } label: {
                    Label("Add key sound…", systemImage: "plus.circle")
                }
                .buttonStyle(.link)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    openWindow(id: SettingsView.windowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// One custom key in the popover: name, file, and preview / change / remove.
private struct MenuKeySoundRow: View {
    @EnvironmentObject private var model: AppModel
    let keySound: KeySound

    var body: some View {
        HStack(spacing: 6) {
            Text(KeyCode.name(for: keySound.keyCode))
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            Group {
                if let file = keySound.down {
                    let broken = model.brokenSounds.contains(file)
                    Text(file)
                        .foregroundStyle(broken ? Color.orange : Color.primary)
                        .help(broken ? "This file is missing or can't be decoded" : file)
                } else {
                    Text("Built-in").foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { model.preview(keyCode: keySound.keyCode, slot: .down) } label: {
                Image(systemName: "play.fill")
            }
            .help("Preview")
            Button { model.chooseSound(keyCode: keySound.keyCode, slot: .down) } label: {
                Image(systemName: "pencil")
            }
            .help("Choose a different file")
            Button { model.removeKey(keySound.keyCode) } label: {
                Image(systemName: "trash")
            }
            .help("Remove this key's custom sound")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct PermissionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Needs Input Monitoring permission", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.semibold))
            Text("Turn on KeyClack in System Settings › Privacy & Security › Input Monitoring. KeyClack only listens; it never changes what you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings") { model.openInputMonitoringSettings() }
                Button("Relaunch") { model.relaunch() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}
