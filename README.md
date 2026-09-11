# Cue

Cue is a native macOS interview overlay: local-first OpenAI chat with Tahoe liquid glass, speaker listen, passive remote control, and a project (code) mode that answers from a local codebase through the Codex CLI. Halo (Electron) is the behavior spec; Cue implements it with AppKit, ScreenCaptureKit, Accessibility, and Keychain.

Requires **macOS 26.5** (Tahoe) and Xcode 26.

## Run

1. Open `Cue.xcodeproj` and run the **Cue** scheme.
2. Cue appears in the menu bar (no Dock icon). Click the status item or press **⌘⇧H** to show the panel.
3. Open **Settings**, add an OpenAI API key, pick a model, and chat.

Do not run the nested `Halo/` or `AirScript/` trees as part of this target. They are reference sources only.

## Project mode

Open **Load project** in the sidebar (or the workspace switcher → *Open project folder…*) and pick a folder. Chats in that workspace run the [Codex CLI](https://github.com/openai/codex) read-only inside the folder, so answers come from the code. Cue offers to build a small map catalog after opening; skipping is fine — Codex explores on demand.

Cue looks for `codex` on your PATH, in Homebrew / npm global installs, or inside Halo.app; set an explicit path in **Settings → Projects** if needed (`npm i -g @openai/codex` installs it). The composer's model and thinking effort apply to project chats too.

Several chats can stream at once: send in one, switch to another and send again. The sidebar shows which chats are still responding and marks finished background replies.

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
