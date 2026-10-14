import AppKit
import KeyClackCore
import SwiftUI

/// Waits for the next key press (including modifiers) and reports its key code, or
/// `KeyCode.allOtherKeys` if the user picks that instead. While it's shown, key presses are
/// swallowed, so pressing e.g. Escape or Return selects that key instead of closing anything.
struct KeyCaptureBox: View {
    let onCapture: (Int) -> Void
    let onCancel: () -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Press the key you want a sound for")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Any key works, including Shift, Command, Escape and Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("All other keys") { finish(KeyCode.allOtherKeys) }
                    .help("One sound for every key that doesn't have its own")
                Button("Cancel", action: onCancel)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: install)
        .onDisappear(perform: uninstall)
    }

    private func finish(_ keyCode: Int) {
        uninstall()
        onCapture(keyCode)
    }

    private func install() {
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // flagsChanged fires on release too; only take presses (some modifier now set).
            if event.type == .flagsChanged,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                return nil
            }
            finish(Int(event.keyCode))
            return nil
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Picker for the base sound: built-in synthesized clicks or an installed Mechvibes pack.
struct SoundSourcePicker: View {
    @EnvironmentObject private var model: AppModel
    var label = "Sound"

    var body: some View {
        HStack {
            Picker(label, selection: $model.config.pack) {
                Text("Built-in click").tag(String?.none)
                if !model.packs.isEmpty {
                    Divider()
                    ForEach(model.packs) { pack in
                        Text(pack.name).tag(String?.some(pack.folder))
                    }
                }
            }
            Menu {
                Button("Add Sound Pack…") { model.addPack() }
                Button("Show Packs Folder") { model.revealPacksFolder() }
                Button("Reload Packs") { model.refreshPacks() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a Mechvibes sound pack")
        }
    }
}
