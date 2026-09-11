# Cue

Cue is a native macOS interview overlay: local-first OpenAI chat with Tahoe liquid glass, speaker listen, and passive remote control. Halo (Electron) is the behavior spec; Cue implements it with AppKit, ScreenCaptureKit, Accessibility, and Keychain.

Requires **macOS 26.5** (Tahoe) and Xcode 26.

## Run

1. Open `Cue.xcodeproj` and run the **Cue** scheme.
2. Cue appears in the menu bar (no Dock icon). Click the status item or press **⌘⇧H** to show the panel.
3. Open **Settings**, add an OpenAI API key, pick a model, and chat.

Do not run the nested `Halo/` or `AirScript/` trees as part of this target. They are reference sources only.

## Permissions

Grant these in System Settings when prompted:

- **Accessibility** — remote typing and Live Captions listen
- **Screen Recording** — screenshots and system-audio listen
- **Speech Recognition** — Apple Speech listen mode

For Accessibility listen, also enable **Live Captions** (System Settings → Accessibility).

## Listen modes

- **Whisper** — ScreenCaptureKit speaker audio + on-device WhisperKit
- **Apple Speech** — same audio path + SpeechAnalyzer
- **Accessibility** — scrapes Apple Live Captions via AX (no audio in Cue)

## Validate

Product logic is covered by `CueTests`. UITests launch the accessory app.
