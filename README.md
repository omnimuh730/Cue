# Cue

Cue is a native macOS interview overlay: local-first OpenAI chat with Tahoe liquid glass, speaker listen, passive remote control, and a project (code) mode that answers from a local codebase through the Codex CLI. Halo (Electron) is the behavior spec; Cue implements it with AppKit, ScreenCaptureKit, Accessibility, and Keychain.

Requires **macOS 26.5** (Tahoe) and Xcode 26.

## Run

1. Open `Cue.xcodeproj` and run the **Cue** scheme.
2. Cue appears in the menu bar (no Dock icon). Click the status item or press **⌘⇧H** to show the panel.
3. Open **Settings**, add an OpenAI API key, pick a model, and chat.

Do not run the nested `Halo/` or `AirScript/` trees as part of this target. They are reference sources only.

## Chats

Hover a message for **Copy**, **Regenerate** (the menu picks another model), **Edit** (sends again; later turns are removed), and **Delete from here**. A reply that failed — no network, a stopped stream — shows **Retry** next to the error. Right-click a chat in the sidebar to rename, pin, export as Markdown, or delete it; **Undo** is offered for a few seconds after a delete. **⌘K** searches titles and messages, **⌘[** / **⌘]** switch chats, and **Esc** closes whatever is open or stops the reply on screen.

## Branches

Cue treats a chat like a git branch. **Fork** on any message — the hover row under a bubble, the tab bar's **+**, or a chat's context menu — copies the thread up to that turn into a new branch and leaves the original exactly as it was, so both versions live on. The first fork makes a tab bar appear under the toolbar: `main` and the forks beside it. Click a tab to switch, double-click to rename it, **⌥⌘[** / **⌥⌘]** step through them, and the **×** on a fork deletes it (anything forked out of it reattaches to its parent, and **Undo** puts it back).

Where a thread split, the turn it was cut at carries a **Forked here** line with a chip per branch. Click a chip and that branch's own follow-up turns open underneath as a thread — what it went on to ask, without the history it inherited — and clicking any of those turns opens the branch on it.

The sidebar still shows one row per chat however many branches it has; the row carries a branch count and reopens on the branch you last read. Deleting the row deletes the thread with all of its branches.

Select any text in a message and two actions float over it: **Add to chat** quotes the passage into the composer, and **Fork** branches the chat at that message and carries the quote into the new branch's composer — the way to ask a follow-up about one part of an answer without derailing the thread it came from.

## Files

Attach PDF, Word, Excel, PowerPoint, images, Markdown, and other text files with the paperclip, by dropping them on the composer, or by pasting a file with ⌘V. PDFs go to OpenAI as-is; Office files are read on your Mac with Apple frameworks (no plugins) and sent as text. Click a chip to preview it.

## Web search

Turn **Settings → Chat → Web search** on for every message, or type `@web_search` in the composer to search for just that one. Answers that used search show numbered source chips underneath; click one to open it, and **Copy** includes the list.

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

While listen is armed, a **Heard** strip above the composer shows the latest lines. Press **⌘num1** to answer the last sentence heard, **⌘num3** for the last three, or **⌘num0** for everything since the last answer; **Answer** in the strip does the same as ⌘num1, and clicking a line adds it to the draft. Anything you had typed is kept. Turn off **Settings → Listen → Insert speech into the draft** if you only want the strip.

## Validate

Product logic is covered by `CueTests`. UITests launch the accessory app.
