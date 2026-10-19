# Zen

Zen is a macOS voice-memo and media transcription app. Press **Option+Space** from anywhere to record a memo, press it again to stop, and Zen transcribes it completely on-device using **Voz** or **Phonon-2** (Apple Neural Engine). The transcript is copied to the clipboard, saved locally, and shown in the memo grid.

You can also drop any video or audio file into the **Transcribe** tab to extract audio and transcribe it on-device with zero external API calls.

## Requirements

- macOS 26.5 or later
- Xcode 17 or later
- Microphone access
- No API keys required (runs 100% on-device using Voz or Phonon-2 via Core ML)

## Usage

1. Launch Zen, learn the Option+Space shortcut, and enable microphone access when you are ready. Model selection is available in Settings.
2. Press **Option+Space** to start recording.
3. Speak, then press **Option+Space** again to stop.
4. Wait for the on-device transcription to finish. The result is copied to the clipboard automatically and, with Accessibility enabled, pasted into the input where you started recording.

Enable **Settings → Automatic paste → Paste after recording** and click **Set up automatic paste…** to set up access. A glass guide appears at the bottom of System Settings. Drag the Zen app row into **Privacy & Security → Accessibility**, then turn on its switch. Dragging adds the app; permission is granted only when you enable it. The guide follows the Settings window and closes once access is enabled. Input Monitoring is not needed for the existing Option+Space shortcut. Settings also includes a test input: click it, press Option+Space to record, then press the shortcut again to stop. The status beneath it explains when a result falls back to the clipboard.

Automatic paste is limited to shortcut recordings and the original editable input. If there was no input, focus changed, the app does not expose an editable input through Accessibility, or permission is unavailable, the result stays on the clipboard. Zen never activates another app, pastes into password fields, or submits the text. File transcription retains its existing copy/export behavior.

In the **Memos** tab, you can:

- Hover over a memo to copy it again or delete it.
- Choose a background color with the paintbrush button; text automatically uses a contrasting shade.
- Pinch to preview the grid size, then release to settle into the nearest layout.

In the **Transcribe** tab, you can:

- Drag and drop any video (`.mp4`, `.mov`, `.m4v`, etc.) or audio file (`.mp3`, `.wav`, `.m4a`, `.aac`, `.flac`, etc.).
- Audio is extracted from video files automatically.
- Transcribe on-device using the Apple Neural Engine.
- Copy the transcript, add it to Memos, or export it as a `.txt` file.

## Welcome experience

The introduction has six screens: welcome, the Option+Space shortcut and saved transcripts, on-device transcription, model selection and download, optional automatic-paste setup, and microphone setup. Every screen is shown in sequence, including when replaying with microphone access already granted. Use the arrows to move forward and back. Accessibility is requested only after clicking **Enable automatic paste**; microphone access is requested only after clicking **Enable microphone**. You can skip either permission and continue with clipboard results or file transcription. Choose Voz or Phonon-2 on the model screen, then click **Download & Prepare**. Download progress, preparation, and retry states appear there. You can download later or continue while preparation runs in the background. The same saved model selection and preparation status remain available in Settings.

Completion is saved between launches. Use **Window → Onboarding** or **Settings → Replay introduction** to revisit it in a separate window. Each replay starts at the welcome screen. Text reveals word by word when each screen appears. Reduce Motion uses a short fade without movement or stagger. Completed installations warm cached models at startup; missing models download only when you prepare them or start transcription.

For a first-launch demonstration, right-click Zen’s Dock icon and choose **Demo Onboarding**. A blurred bloom expands over the desktop into a pink-and-burgundy window, reveals the bird, and dissolves into the first walkthrough screen. The original bundled score shares cue points with the visual timeline. Use the speaker control to mute, or **Escape / Skip intro** to go straight to onboarding. Reduce Motion uses a short window fade without the bloom or score. Replaying restarts the sequence and cancels the previous audio and animation. The main app remains hidden until the walkthrough is finished, without resetting the saved onboarding status.

The Dock menu also works while Zen is fully quit: the bundled `ZenDockTilePlugin.docktileplugin` supplies the item and launches directly into the demo. Keep the installed app in the Dock. After upgrading from a version without the plug-in, remove the old Dock icon and drag the installed app back once to refresh it. If macOS disables the extension, enable Zen under **System Settings → General → Login Items & Extensions → Dock Tiles**. The plug-in and the running app share one menu item; normal launches still open the main app.

Cold demo launches wait for app initialization and an onscreen intro panel before starting the music and animation clocks. Launch delays cannot consume the opening blob or skip directly to the first page.

Finishing onboarding expands the main window to at least 92% of its screen’s usable area, keeping an already larger or full-screen window as it is. New main windows default to 1280 × 820 after setup; the separate onboarding window remains compact. Normal launches still open the app. To regenerate the original intro audio, run `python3 scripts/generate-onboarding-audio.py`; it reads visual landmarks directly from `OnboardingIntroTiming`. The original melody and opening volume are preserved, with a quieter final chord an octave lower after the window reveal, followed by a smooth fade. Visuals and handoff follow the audio playhead when audio is available, with a monotonic-clock fallback for silent playback.

## Transcription models

Open **Zen → Settings…** (**Command+,**) or the toolbar gear to choose a model. The selection is saved and used by both recording and file transcription. An in-progress transcription keeps the model it started with.

- **Voz** is the default and supports multilingual transcription.
- **Phonon-2** transcribes English on Apple silicon using Fermion Research's [native Swift/Core ML package](https://github.com/fermionresearch/phonon-coreml), pinned to version 1.1.2. It needs no Python installation or API server.

Choose **Download & Prepare** to get a model ready before recording, or let it prepare on first use. Downloads are verified and cached locally; the first Core ML preparation can take a few minutes. A network connection is needed for the initial download, then transcription works offline. Settings shows progress and lets you retry failed preparation.

Phonon-2 weights are downloaded from [FermionResearch/Phonon-2-CoreML](https://huggingface.co/FermionResearch/Phonon-2-CoreML) at revision `1143812fd4236522232a8c33e3115f0577e3cd7d`. Phonon-2 is by Fermion Research, derived from NVIDIA Parakeet TDT; weights are licensed under **CC BY 4.0** and the Swift runtime under **Apache 2.0**. The original notices and licenses are stored with the downloaded model.

## Data storage

- Memo history: `~/Library/Application Support/transcript_history.json`
- Transcript text files: `~/Library/Application Support/Transcripts/`
- History is limited to the 100 most recent transcripts.
- Model weights: `~/Library/Caches/desert-ant-models/` (separate directories for each model and revision).
- Compiled Phonon-2 models: `~/Library/Caches/phonon-coreml/`.
- Temporary recordings are written to the system temporary directory and deleted after processing.

## Architecture

```text
Option+Space (or File Drop in Transcribe Tab)
    |
HotkeyManager / TranscribeView
    |
AudioRecorder / AudioExtractionService -> 16 kHz WAV
    |
TranscriptionService -> selected model: Voz or Phonon-2 (Core ML / Neural Engine)
    |
ZenState -> clipboard, local files, memo grid
```

Key modules:

- `zen/zenApp.swift`: app startup, model warm-up, and dependency wiring.
- `zen/Components/HotkeyManager.swift`: global Carbon hotkey registration.
- `zen/Components/PillPanelManager.swift`: floating recording-status panel and recording state transitions.
- `zen/Components/AudioRecorder.swift`: microphone capture, audio-level monitoring, and WAV conversion.
- `zen/Components/AudioExtractionService.swift`: audio extraction from video and audio normalization.
- `zen/Components/TranscriptionService.swift`: model selection, preparation, on-device transcription, clipboard copy, and local export.
- `zen/Components/TranscribeView.swift`: drag-and-drop video/audio transcription interface.
- `zen/Components/TranscribeViewModel.swift`: pipeline orchestration and UI state for media transcription.
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

The project has the `zen` application target and an embedded `ZenDockTilePlugin` bundle target, with no automated test target. Build the application scheme to include both. The Dock plug-in uses Apple's `NSDockTilePlugIn` API and is intended for direct distribution outside the Mac App Store. Sign the nested plug-in before signing the application when packaging a release.

Model preference, cancellation, and timestamp grouping checks are available after building Release with `-derivedDataPath build`:

```bash
python3 scripts/check-transcription.py
```

Automatic-paste fallback and focus checks run without model downloads, Accessibility prompts, or keystrokes sent to other apps:

```bash
python3 scripts/check-auto-paste.py
```

Pass the path to the official `ci/clips/1089-134686-0002.flac` clip from the Phonon-2 model repository to also verify both engines against known speech. This downloads missing model weights and prepares Core ML on first run.

## Notes

- The first recording prompts for microphone permission.
- The app uses a non-sandboxed target because it registers a global hotkey and accesses system audio services.
