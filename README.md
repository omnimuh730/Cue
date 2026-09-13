# Cue

Cue is a native macOS interview overlay: local-first OpenAI chat with Tahoe liquid glass, speaker listen, passive remote control, and a project (code) mode that answers from a local codebase through the Codex CLI. Halo (Electron) is the behavior spec; Cue implements it with AppKit, ScreenCaptureKit, Accessibility, and Keychain.

Requires **macOS 26.5** (Tahoe) and Xcode 26.

## Run

1. Open `Cue.xcodeproj` and run the **Cue** scheme.
2. Cue appears in the menu bar (no Dock icon). Click the status item or press **⌘⇧H** to show the panel.
3. Open **Settings**, add an OpenAI API key, pick a model, and chat.

Do not run the nested `Halo/` or `AirScript/` trees as part of this target. They are reference sources only.

## Files

Attach PDF, Word, Excel, PowerPoint, images, Markdown, and other text files with the paperclip, by dropping them on the composer, or by pasting a file with ⌘V. PDFs go to OpenAI as-is; Office files are read on your Mac with Apple frameworks (no plugins) and sent as text. Click a chip to preview it.

## Skills

Put Markdown files in `~/.cue/skills/` — either `name.md` or `name/SKILL.md`, optionally starting with a front-matter block that sets `name:` and `description:`. Type `/` in the composer to pick one; it attaches as a chip and the model follows it for that message. Projects with a code folder also pick up `.cue/skills` and `.claude/skills` inside that folder. **Settings → Skills** lists what is loaded.

## Projects

**New project** in the sidebar creates a workspace with its own instructions and knowledge files; chats started inside it use both on every turn. Open the project's settings (slider icon on its row) to edit instructions, add knowledge (drop files or use *Add files…*), or link a code folder.

### Code mode

Link a code folder in project settings (or use *Open code folder* on an empty chat). Chats in that project run the [Codex CLI](https://github.com/openai/codex) read-only inside the folder, so answers come from the code. Cue offers to build a small map catalog after linking; skipping is fine — Codex explores on demand.

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
