# Zen

Zen is a macOS voice-memo app. Press **Option+Space** (or your own shortcut) from anywhere to record a memo, press it again to stop, and Zen transcribes it completely on-device using **Voz** or **Phonon-2** (Apple Neural Engine). The transcript is copied to the clipboard, saved locally, and shown in the memo grid.

## Requirements

- macOS 26.5 or later on a Mac with Apple silicon
- Xcode 17 or later
- Microphone access
- No API keys required (runs 100% on-device using Voz or Phonon-2 via Core ML)

## Usage

1. Launch Zen, learn the recording shortcut (or choose your own), and enable microphone access when you are ready. Model selection is available in Settings.
2. Press **Option+Space** to start recording.
3. Speak, then press **Option+Space** again to stop.
4. Wait for the on-device transcription to finish. The result is copied to the clipboard automatically and, with Accessibility enabled, pasted into the input where you started recording.

Enable **Settings → General → Paste after recording** and click **Set up…** to set up access. A glass guide appears at the bottom of System Settings. Drag the Zen app row into **Privacy & Security → Accessibility**, then turn on its switch. Dragging adds the app; permission is granted only when you enable it. The guide follows the Settings window and closes once access is enabled. Input Monitoring is not needed for the recording shortcut. The General tab also includes a test input: click it, press your recording shortcut to record, then press the shortcut again to stop. The status beneath it explains when a result falls back to the clipboard.

Automatic paste is limited to shortcut recordings and the original editable input. If there was no input, focus changed, the app does not expose an editable input through Accessibility, or permission is unavailable, the result stays on the clipboard. Zen never activates another app, pastes into password fields, or submits the text.

The main window shows your memos. You can:

- Hover over a memo to copy it again or delete it.
- Choose a background color with the paintbrush button; text automatically uses a contrasting shade.
- Pinch to preview the grid size, then release to settle into the nearest layout.

## Recording shortcut

The default shortcut is **Option+Space**. To change it, open **Settings → General**, click the shortcut and press a new key combination. You can also choose **Use a different shortcut** on the onboarding shortcut screen. Press **Escape** to cancel, or use the reset button to return to Option+Space. Your choice is saved between launches and appears throughout the app.

A shortcut needs Control, Option or Command, unless it's a function key (F1–F20). Combinations used by macOS or standard editing, such as ⌘C, ⌘Space and the screenshot shortcuts, are rejected. ⌘V is also rejected because automatic paste uses it. If the shortcut can't be registered, for example because another app already uses it, Zen keeps your previous shortcut and explains why in Settings.

## Welcome experience

The introduction has six screens: welcome, the recording shortcut and saved transcripts, on-device transcription, model selection and download, optional automatic-paste setup, and microphone setup. Every screen is shown in sequence, including when replaying with microphone access already granted. Use the arrows to move forward and back. Accessibility is requested only after clicking **Enable automatic paste**; microphone access is requested only after clicking **Enable microphone**. You can skip either permission and grant it later; without automatic paste, results stay on the clipboard. Choose Voz or Phonon-2 on the model screen, then click **Download & Prepare**. Download progress, preparation, and retry states appear there. You can download later or continue while preparation runs in the background. The same saved model selection and preparation status remain available in Settings.

Completion is saved between launches. Use **Window → Onboarding** or **Settings → About → Replay** to revisit it in a separate window. Each replay starts at the welcome screen. Text reveals word by word when each screen appears. Reduce Motion uses a short fade without movement or stagger. Completed installations warm cached models at startup; missing models download only when you prepare them or start transcription.

On first launch, a blurred bloom expands over the desktop into a pink-and-burgundy window, writes the handwritten “zen” wordmark stroke by stroke, and dissolves into the welcome screen. The original bundled score shares cue points with the visual timeline. Use the speaker control to mute, or **Escape / Skip intro** to go straight to onboarding. Reduce Motion uses a short window fade without the bloom or score. The main app stays hidden until the walkthrough is finished. Quitting before then plays the intro again on the next launch.

Debug builds add **Demo Onboarding** to Zen’s Dock menu, which replays the intro and walkthrough without resetting the saved onboarding status. Replaying restarts the sequence and cancels the previous audio and animation. The bundled `ZenDockTilePlugin.docktileplugin` supplies the item while Zen is fully quit and launches directly into the demo. Keep the installed app in the Dock. After upgrading from a version without the plug-in, remove the old Dock icon and drag the installed app back once to refresh it. If macOS disables the extension, enable Zen under **System Settings → General → Login Items & Extensions → Dock Tiles**. The plug-in and the running app share one menu item; normal launches still open the main app. Release builds have no Dock menu item.

Cold demo launches wait for app initialization and an onscreen intro panel before starting the music and animation clocks. Launch delays cannot consume the opening blob or skip directly to the first page.

Finishing onboarding expands the main window to at least 92% of its screen’s usable area, keeping an already larger or full-screen window as it is. New main windows default to 1280 × 820 after setup; the separate onboarding window remains compact. Normal launches still open the app. To regenerate the original intro audio, run `python3 scripts/generate-onboarding-audio.py`; it reads visual landmarks directly from `OnboardingIntroTiming`. The handwriting follows a per-pixel pen-timing map, `zen/Resources/ZenLogoArrival.png`. If the logo changes, regenerate it with `python3 scripts/generate-logo-arrival.py`, which needs numpy, scipy, scikit-image and Pillow. The original melody and opening volume are preserved, with a quieter final chord an octave lower after the window reveal, followed by a smooth fade. Visuals and handoff follow the audio playhead when audio is available, with a monotonic-clock fallback for silent playback.

## Transcription models

Open **Zen → Settings…** (**Command+,**) or the toolbar gear, then the **Model** tab, to choose a model. The selection is saved and used for every recording. An in-progress transcription keeps the model it started with.

| Model | Languages | Size | Speed | WER |
|---|---|---|---|---|
| **Voz** (default) | 25 | 467 MB | ~290× real time | 7.40% |
| **Phonon-2** | English | 345 MB | ~400× real time | 5.21% |

Both are derived from NVIDIA Parakeet TDT 0.6B v3 and give word timestamps. Sizes are what Zen downloads. Phonon-2's original MLX release is 164 MB, but Zen uses its Core ML build. Figures come from each model's published card. WER is the mean over the Open ASR Leaderboard's English sets: six for Voz, seven for Phonon-2. Speed depends on the Mac. The same cards appear on the onboarding model screen and in **Settings → Model**. Each card shows whether that model is installed, downloading, or ready. Selecting an installed model loads it in the background, so the next recording doesn't wait.

Core ML compiles each model for the Neural Engine the first time it runs on a Mac. This takes about 20 seconds for Voz and up to a minute for Phonon-2, measured on an M-series Mac. After that, macOS caches the result and loads take well under a second, including after app updates.

- **Voz** is the default and supports multilingual transcription.
- **Phonon-2** transcribes English on Apple silicon using Fermion Research's [native Swift/Core ML package](https://github.com/fermionresearch/phonon-coreml), pinned to version 1.1.2. It needs no Python installation or API server.

Choose **Download & Prepare** to get a model ready before recording, or let it prepare on first use. Downloads are verified and cached locally; the first Core ML preparation can take a few minutes. A network connection is needed for the initial download, then transcription works offline. Settings shows progress and lets you retry failed preparation.

Phonon-2 weights are downloaded from [FermionResearch/Phonon-2-CoreML](https://huggingface.co/FermionResearch/Phonon-2-CoreML) at revision `1143812fd4236522232a8c33e3115f0577e3cd7d`. Phonon-2 is by Fermion Research, derived from NVIDIA Parakeet TDT; weights are licensed under **CC BY 4.0** and the Swift runtime under **Apache 2.0**. The original notices and licenses are stored with the downloaded model.

## Data storage

- Memo history: `~/Library/Application Support/pipper.dev.zen/transcript_history.json`
- Transcript text files: `~/Library/Application Support/pipper.dev.zen/Transcripts/`
- Earlier versions stored these directly in `~/Library/Application Support/`. On launch, Zen moves its history file and `transcript_*.txt` files into the folder above and leaves anything else in place. If an older version saves memos to the old location after that move, they're merged in the next time Zen launches.
- History is limited to the 100 most recent transcripts. Each memo has its own ID, so deleting one of several identical memos removes only the one you chose. History saved by earlier versions gets IDs on first launch.
- Model weights: `~/Library/Caches/desert-ant-models/` (separate directories for each model and revision).
- Compiled Phonon-2 models: `~/Library/Caches/phonon-coreml/`.
- Temporary recordings are written to the system temporary directory and deleted after processing.

## Architecture

```text
Recording shortcut
    |
HotkeyManager -> PillPanelManager
    |
AudioRecorder -> 16 kHz WAV
    |
TranscriptionService -> selected model: Voz or Phonon-2 (Core ML / Neural Engine)
    |
ZenState -> clipboard, local files, memo grid
```

Key modules:

- `zen/zenApp.swift`: app startup, model warm-up, and dependency wiring.
- `zen/Components/HotkeyManager.swift`: global Carbon hotkey registration, debouncing, and shortcut changes.
- `zen/model/RecordingShortcut.swift`: the saved shortcut, its display names, and validation.
- `zen/Components/ShortcutRecorder.swift`: the shortcut recorder used in Settings and onboarding.
- `zen/Components/PillPanelManager.swift`: floating recording-status panel and recording state transitions.
- `zen/Components/AudioRecorder.swift`: microphone capture, audio-level monitoring, and WAV conversion.
- `zen/Components/TranscriptionService.swift`: model selection, preparation, on-device transcription, clipboard copy, and local export.
- `zen/Components/ZenState.swift`: shared observable state and transcript history persistence.
- `zen/Components/GridView.swift`: memo grid, zoom presets, copy, and delete actions.

## Build

From the repository root:

```bash
xcodebuild -project zen.xcodeproj \
  -scheme zen \
  -configuration Debug \
  -sdk macosx \
  build \
  CODE_SIGNING_ALLOWED=NO
```

The project has the `zen` application target, which builds `Zen.app`, and an embedded `ZenDockTilePlugin` bundle target, with no automated test target. Build the application scheme to include both. The Dock plug-in uses Apple's `NSDockTilePlugIn` API and is intended for direct distribution outside the Mac App Store. Both targets use the hardened runtime; microphone access is granted by `Configuration/Zen.entitlements`. Builds are Apple silicon only, because Phonon-2's Core ML runtime uses `Float16`, which Intel Macs don't support.

Model preference, cancellation, and timestamp grouping checks are available after building Release with `-derivedDataPath build`:

```bash
python3 scripts/check-transcription.py
```

Shortcut capture checks feed real key events through the recorder and briefly register a global hotkey, so run them with Zen quit:

```bash
python3 scripts/check-shortcut-capture.py
```

Shortcut, memo history, and storage migration checks run without registering hotkeys or touching your data:

```bash
python3 scripts/check-state.py
```

Automatic-paste fallback and focus checks run without model downloads, Accessibility prompts, or keystrokes sent to other apps:

```bash
python3 scripts/check-auto-paste.py
```

Pass the path to the official `ci/clips/1089-134686-0002.flac` clip from the Phonon-2 model repository to also verify both engines against known speech. This downloads missing model weights and prepares Core ML on first run.

## Releasing

`scripts/release.sh` builds a Release copy of `Zen.app`. It signs it with your Developer ID (the Dock plug-in first, then the app), notarizes and staples the app, then packages, signs, notarizes, and staples `dist/Zen-<version>-<build>.dmg`.

One-time setup:

1. Join the Apple Developer Program. Then create a **Developer ID Application** certificate at [developer.apple.com](https://developer.apple.com/account/resources/certificates) and install it in your login keychain.
2. Create an app-specific password at [account.apple.com](https://account.apple.com). Then store notarization credentials in your keychain:

```bash
xcrun notarytool store-credentials zen-notary --apple-id you@example.com --team-id YOURTEAMID
```

Then, for each release:

```bash
scripts/release.sh
```

Raise `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in the project before each release. Testers then get a new file name, and the build number increases. The script picks the only Developer ID Application identity in your keychain. If you have several, set `ZEN_SIGNING_IDENTITY`. Set `ZEN_NOTARY_PROFILE` to use a profile other than `zen-notary`. Notarization usually takes a few minutes per submission, and there are two submissions: the app, then the DMG.

`scripts/release.sh --skip-notarize` signs and packages without notarizing. `--adhoc` builds without a certificate and leaves the DMG unsigned: it opens anywhere, but Zen.app won't open on other Macs until `xattr -cr /Applications/Zen.app` clears its quarantine. An ad-hoc signed DMG wouldn't open at all.

## Website

The marketing site lives in `site/`, a small Astro project with a landing page and a download page. Both pages always fit one screen and never scroll. It builds to static HTML and doesn't affect the Xcode project.

```bash
cd site && npm install && npm run dev
```

The social preview image is `site/public/og.png`, at 1200 × 630.

Deploy it on Vercel with **Root Directory** set to `site`; Vercel detects Astro. The download page links to `https://github.com/maker-or/zen/releases/latest/download/Zen.dmg`, so attach the DMG to each GitHub release under the exact name `Zen.dmg`. `/download?steps` shows the install steps without starting another download.

## Notes

- Zen logs shortcut, recording, and model events to the unified log. To see them:

```bash
/usr/bin/log show --last 15m --predicate 'subsystem == "pipper.dev.zen"' --info --style compact
```

- The first recording prompts for microphone permission.
- The app uses a non-sandboxed target because it registers a global hotkey and accesses system audio services.
