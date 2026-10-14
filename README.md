# KeyClack

A tiny macOS menu-bar app that makes your MacBook keyboard sound like a mechanical one, and
lets you give any key its own sound. (Yes, that means Backspace can go *faaa*.)

- **Real keyboard sounds** from [Mechvibes](https://github.com/hainguyents13/mechvibes) sound
  packs: Cherry MX Blue/Brown/Red/Black, Holy Pandas, NK Creams, Topre and more, including
  key-release sounds where the pack has them
- **A sound for any key**: give Backspace, Return or any other key its own press and release
  sound (MP3, WAV, AIFF, M4A, OGG, CAF), or give **All other keys** one shared sound
- A **built-in synthesized click** when no pack is selected (deeper on Space, Return, Shift, …)
- **Quiet** / **Medium** loudness presets plus a volume slider
- Holding a key replays the sound on every auto-repeat (can be turned off)
- On/off switch and an optional **Launch at Login** (off by default)
- Lives in the menu bar only: no Dock icon, no window in your way

No sound files ship with the app or this repo. Sound packs are downloaded to your Mac by a
script (step 4), the fallback click is generated in code, and you bring your own meme clips.

---

## Contents

1. [Requirements](#requirements)
2. [Setup, step by step](#setup-step-by-step)
3. [Using KeyClack](#using-keyclack)
4. [Start and stop from the terminal](#start-and-stop-from-the-terminal)
5. [Troubleshooting](#troubleshooting)
6. [Uninstall](#uninstall)
7. [Privacy](#privacy)
8. [Development](#development)

---

## Requirements

| What | Version |
| --- | --- |
| macOS | 14 Sonoma or later (Apple Silicon or Intel) |
| Swift | 5.10 or later, from **Xcode** or the **Xcode Command Line Tools** |
| git | Comes with the Command Line Tools; needed for the sound-pack download |

There's no prebuilt download yet: you build the app yourself. It takes about a minute.

---

## Setup, step by step

### 1. Install the Xcode Command Line Tools

Skip this if you already have Xcode. Check with:

```sh
swift --version
```

If that prints a Swift version of 5.10 or newer, go to step 2. Otherwise install the tools:

```sh
xcode-select --install
```

A dialog pops up; click **Install** and wait for it to finish, then run `swift --version`
again.

### 2. Get the code

```sh
git clone https://github.com/<your-username>/keyclack.git
cd keyclack
```

(Or download the ZIP from GitHub's green **Code** button and unzip it, then `cd` into the
folder in Terminal.)

### 3. Build the app

```sh
scripts/build-app.sh
```

This compiles a release build and packages it as `build/KeyClack.app`. The first build
takes a minute or so; later ones are faster. When it finishes you'll see:

```
Built build/KeyClack.app
Run it with:  open build/KeyClack.app
```

> If you get `permission denied`, make the scripts executable once with
> `chmod +x scripts/*.sh` and try again.

### 4. Download the keyboard sound packs (recommended)

```sh
scripts/get-mechvibes-packs.sh
```

This downloads the 18 sound packs that ship with Mechvibes into
`~/Library/Application Support/KeyClack/Packs/`. It's safe to run again: packs you already
have are skipped. Without packs, KeyClack still works with its built-in synthesized click.

### 5. Move the app to Applications (recommended)

```sh
cp -R build/KeyClack.app /Applications/
```

Running it from `/Applications` makes **Launch at Login** reliable and keeps it working if you
move or delete the project folder. You can also just drag `build/KeyClack.app` into
`Applications` in Finder.

### 6. Launch it

```sh
open /Applications/KeyClack.app
```

A **keyboard icon** appears in the menu bar at the top of the screen. There is no Dock icon;
that's on purpose.

### 7. Allow Input Monitoring

To hear which keys you press, macOS requires you to grant KeyClack **Input Monitoring**
permission. On first launch:

1. macOS shows a prompt. Click **Open System Settings** (or click the menu-bar icon and press
   **Open Settings**).
2. In **System Settings › Privacy & Security › Input Monitoring**, switch **KeyClack** on.
   If it's not in the list, click **+** and pick `KeyClack.app` from `Applications`.
3. KeyClack notices the change within a few seconds. If you don't hear clicks, click the
   menu-bar icon and press **Relaunch**.

Type something. You should hear it. 🎉

### 8. Pick a sound

Click the menu-bar icon and choose a pack from **Sound** (for example *Cherry MX Blue* or
*Holy Pandas*). Set **Loudness** to **Quiet** or **Medium** and fine-tune with the volume
slider in **Settings…**.

---

## Using KeyClack

Everything is in the menu-bar popover (click the keyboard icon):

| Control | What it does |
| --- | --- |
| **Enabled** | Turns all sounds on or off |
| **Sound** | Picks a sound pack, or **Built-in click** |
| **+** next to Sound | **Add Sound Pack…**, **Show Packs Folder**, **Reload Packs** |
| **Loudness** | Quiet or Medium preset |
| **Release sound on key-up** | Also play a sound when a key is released |
| **Play while a key is held** | Replay the sound on every key-repeat |
| **Custom key sounds** | Your per-key sounds, with ▶ preview, ✎ change and 🗑 remove |
| **Add key sound…** | Give a key its own sound (see below) |
| **Settings…** | Volume slider, Launch at login, press *and* release sounds per key |

### Give a key its own sound (the *faaa* on Backspace)

1. Get an audio file you want to use (MP3, WAV, AIFF, M4A, OGG or CAF).
2. Menu-bar icon → **Add key sound…**
3. Press the key you want, for example **Backspace** (any key works, including Shift, Command,
   Escape and Return).
4. Pick your audio file.

Done: that key now plays your file. To give *every other* key one shared sound, click
**All other keys** in step 3 instead of pressing a key. Release (key-up) sounds per key are
set in **Settings…**.

Which sound plays, in order of priority:

1. The key's own custom file
2. The **All other keys** file
3. The selected sound pack
4. The built-in click

KeyClack copies the files you pick into `~/Library/Application Support/KeyClack/Sounds/`, so
moving or deleting the original later doesn't break anything. Clips longer than 15 seconds are
trimmed.

### More sound packs

Any pack from [mechvibes.com](https://mechvibes.com) works. Download it, then in KeyClack click
**+** next to **Sound** → **Add Sound Pack…** and choose the `.zip` or the unzipped folder.
Both Mechvibes pack layouts are supported (one long recording sliced per key, or one file per
key), including release sounds.

### Launch at login

Open **Settings…** and switch on **Launch at login**. If macOS asks, approve KeyClack in
**System Settings › General › Login Items**.

---

## Start and stop from the terminal

`scripts/keyclack.sh` starts and stops the app from the project folder. `start` rebuilds
first, but only if the code changed since the last build:

```sh
scripts/keyclack.sh start
scripts/keyclack.sh stop
```

Handy shell shortcuts, if you want them (add to `~/.zshrc`, with your real path):

```sh
alias keyclack-on="$HOME/path/to/keyclack/scripts/keyclack.sh start"
alias keyclack-off="$HOME/path/to/keyclack/scripts/keyclack.sh stop"
```

---

## Troubleshooting

**No sound at all**

- Check that **Enabled** is on and your Mac's volume isn't muted.
- Check **System Settings › Privacy & Security › Input Monitoring**: KeyClack must be on.
  Then press **Relaunch** in the menu.

**It worked, then stopped after I rebuilt the app**

The build is *ad-hoc signed*, so macOS treats each new build as a brand-new app. The old
Input Monitoring entry can still show as *on* while silently not applying. Reset it and allow
the prompt again:

```sh
tccutil reset ListenEvent dev.keyclack.KeyClack
open /Applications/KeyClack.app
```

(`scripts/keyclack.sh start` does this automatically when it rebuilds.) To avoid it entirely,
sign with a real identity; a free *Apple Development* certificate from Xcode works:

```sh
CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
```

**macOS says the app "can't be opened" or is from an unidentified developer**

This can happen if you copied the app from another Mac. Right-click `KeyClack.app` → **Open**
→ **Open**. Apps you build yourself on your own Mac don't need this.

**Silent in password fields**

That's macOS *Secure Input*: it hides keystrokes in password fields from every app like this
one. Expected behaviour.

**A sound pack doesn't show up**

Click **+** next to **Sound** → **Reload Packs**. Each pack must be a folder containing a
`config.json` inside `~/Library/Application Support/KeyClack/Packs/`.

**A custom key sound shows as broken**

The file is missing or can't be decoded. Choose it again with ✎, or convert it to MP3/WAV.

---

## Uninstall

```sh
scripts/keyclack.sh stop                                   # or Quit from the menu
rm -rf /Applications/KeyClack.app
rm -rf "$HOME/Library/Application Support/KeyClack"        # settings, packs, your sounds
tccutil reset ListenEvent dev.keyclack.KeyClack            # remove the Input Monitoring entry
```

---

## Privacy

KeyClack uses a **listen-only** event tap: it sees which physical key went up or down so it
can play a sound, and that's all. It never records, stores or sends what you type, makes no
network connections, and can't modify or inject keystrokes. Your settings live in
`~/Library/Application Support/KeyClack/config.json`.

---

## Development

```sh
swift build        # debug build of the library and app
swift test         # unit tests: synthesis, audio decoding, packs, config
scripts/build-app.sh debug    # package a debug build as build/KeyClack.app

# also test-load every installed sound pack
KEYCLACK_PACKS_DIR="$HOME/Library/Application Support/KeyClack/Packs" swift test --filter RealPacks
```

### Project layout

| Path | What it is |
| --- | --- |
| `Sources/KeyClackCore/SoundSynth.swift` | Fallback synthesized click (tick → bottom-out thud → case resonance) |
| `Sources/KeyClackCore/MechvibesPack.swift` | Mechvibes pack loader and libuiohook → macOS key-code table |
| `Sources/KeyClackCore/SoundEngine.swift` | AVAudioEngine with a 24-voice pool for overlapping, low-latency playback |
| `Sources/KeyClackCore/AudioLoader.swift` | Decodes user files and resamples them to the engine format |
| `Sources/KeyClackCore/Config.swift` | Config model and the on-disk store |
| `Sources/KeyClackCore/KeyNames.swift` | macOS virtual key codes → names |
| `Sources/KeyClack/KeyMonitor.swift` | Global listen-only `CGEventTap` (key down/up/modifiers) |
| `Sources/KeyClack/AppModel.swift` | Wires keys → sounds, permissions, login item, file import |
| `Sources/KeyClack/KeyClackApp.swift`, `SettingsView.swift`, `KeyCapture.swift` | SwiftUI menu-bar popover, settings window, key picker and sound picker |
| `Resources/Info.plist` | App bundle metadata (menu-bar only, bundle id `dev.keyclack.KeyClack`) |
| `scripts/build-app.sh` | Builds and signs `build/KeyClack.app` |
| `scripts/keyclack.sh` | Start/stop helper that rebuilds only when the code changed |
| `scripts/get-mechvibes-packs.sh` | Downloads the Mechvibes sound packs |

### Contributing

Issues and pull requests are welcome. Please don't commit audio files you don't own the
rights to; `.gitignore` blocks common audio formats for that reason.

---

## Credits

- Sound packs: [Mechvibes](https://github.com/hainguyents13/mechvibes) by hainguyents13 and its
  community. Packs are downloaded to your Mac for personal use and aren't part of this
  repository; check each pack's own license before redistributing it.
