# Cue architecture

```text
SwiftUI (glass UI)
  └─ NSPanel (nonactivating, stealth, opacity)
       ├─ AppSession (MainActor)
       │    ├─ SwiftData conversations + projects
       │    ├─ Keychain API key
       │    ├─ URLSession Responses client (Personal workspace)
       │    └─ Codex CLI client (project workspaces, `Process` + JSONL)
       ├─ ListenController
       │    ├─ WhisperKit (SCK audio)
       │    ├─ SpeechAnalyzer (SCK audio)
       │    └─ Live Captions AX (no audio)
       ├─ RemoteControlSession (CGEvent tap + click shield)
       └─ NSStatusItem + global hotkeys
```

## Window policy

Cue is an accessory (`LSUIElement`). The panel is an `NSPanel` with `.nonactivatingPanel`. Close orders it out; Quit comes from the status item or the quit hotkey. Stealth sets `sharingType = .none`. Passive focus uses `orderFrontRegardless()` and never `makeKeyAndOrderFront` unless the user is interacting with Cue.

App Sandbox is **off** so ScreenCaptureKit loopback, Accessibility, and session event taps work. Hardened Runtime stays on.

## Chat

`ResponsesClient` streams `POST /v1/responses` with `store: true`. Follow-ups send `previous_response_id` plus new user turns. If OpenAI returns `previous_response_not_found`, Cue replays the full local thread.

Turns run per conversation: `AppSession` keeps one `ChatRequest` (task + cancellation token) per streaming conversation, so several chats can answer at once. The sidebar shows a live indicator and the agent's progress line for each streaming chat, an unread dot once a background reply lands, and the composer's send button only stops the on-screen conversation. Drafts are parked per conversation when switching.

Streaming is paced, not per token: deltas are batched into the model at 25 fps and SwiftData is committed at most once a second while a turn runs (and at turn end). `ChatView` iterates `Message` objects, so a delta re-renders only its bubble. Assistant Markdown is split by `MarkdownBlocks` (`Shared/`) into paragraph, heading, list, block quote, pipe table, rule, code, and Mermaid blocks; `MarkdownRenderer` parses inline Markdown off the main thread and reuses already-parsed blocks, so a streaming update costs one trailing block. A table only counts once its `|---|` separator has arrived, so a table being streamed does not flicker between prose and grid.

Prose blocks are drawn as one selectable TextKit 1 run (`MarkdownTextBuilder`): lists use a hanging indent with a tab stop for the marker column, tables are `NSTextTable` cells that wrap rather than scroll, and wrapped lines inside a list item or quote are line separators (U+2028) so they stay in the item's paragraph. Block quotes and rules are tagged with custom attributes (`quoteAttribute`, `ruleAttribute`) and `SelectableNSTextView` draws the bar and hairline itself — on macOS 26 TextKit lays out a plain `NSTextBlock`'s padding but never paints its borders or background. Fenced code is tokenized once per block by `CodeHighlighter` (strings, comments, numbers, keywords per language, plus decorators / preprocessor / shell variables / keys / tags) into UTF-16 spans that are cached with the block; `CodeTheme` maps the six token classes onto system dynamic colors. Blocks over 20k characters stay plain.

Mermaid renders in a `WKWebView` once the turn completes (source while streaming) from a bundled host page (`Resources/Mermaid`, no network; the 3.5 MB library is only loaded for uncached diagrams). Rendered SVG and measured height are cached per source so reopening a chat is instant and never reflows. Mermaid's DOMPurify pass drops the root `<svg id>` under WebKit, which orphans its scoped stylesheet; the host page re-applies the id after injection. Zoom is the web view's native page magnification (`MermaidWebContentView`): pinch and smart-zoom are native, ⌘-scroll zooms toward the cursor, scroll or drag pans via `window.scrollBy` while zoomed, double-click resets, and unzoomed scrolls are passed up so the chat scrolls through diagrams.

Message actions live on a hover row under each bubble (`MessageBubble.actionRow`): Copy, Regenerate (with a model submenu) on the newest reply, Edit on user turns (an in-place editor; ⌘⏎ sends, esc cancels), Delete from here, and the time. A failed reply shows **Retry** beside the error at all times. All of them go through `AppSession.truncate(_:at:inclusive:)`, which stops the stream, deletes the later `Message`s, and drops `codexThreadID` (the Codex thread no longer matches; `CodexPrompt` carries the surviving turns), then `startTurn(in:apiKey:model:)` — the half of `send()` that streams a reply to the conversation as it stands. `TurnTruncation` (`Shared/`) holds the pure rule for which turns survive.

Chats can be renamed (double-click or the row's context menu; `titleIsCustom` stops auto-titling), pinned (`pinnedAt`, `ConversationOrder` sorts pinned first), and deleted with Undo: `deleteConversation` soft-deletes (`deletedAt`), the notice offers Undo for 6 s, and `reloadConversations` purges rows older than `undoWindow`. The context menu also exports the chat as Markdown (`ConversationExport`). `notify(_:actionLabel:autoDismiss:action:)` is the one transient banner (`NoticeBanner` in `RootView`); errors linger until tapped, confirmations time out. Esc closes the topmost overlay or, with nothing open, stops the on-screen reply (`dismissTopmost`); ⌘[ / ⌘] move through the sidebar. ⌘K search (`ChatSearch`) lists title hits then message hits with a ±60-character snippet, scoped to the selected project by default, with arrow keys and Return; opening a message hit sets `scrollTarget` and `ChatView` centers on it.

There is no title bar: the sidebar row's info button opens `ThreadInfoView` (cost, tokens with prompt-cache share, latency, per-reply breakdown). Personal turns send a per-thread `prompt_cache_key` so OpenAI serves the shared prefix from cache.

## Attachments

`MessageAttachment` carries a `kind`: `image` (JPEG data URL), `pdf` (data URL plus PDFKit text), `document` (Office / RTF reduced to text), `text` (file contents), or `skill`. `FileAttachmentImporter` turns a URL into one off the main actor using only Apple frameworks: PDFKit, AppKit's text importers for `.doc` / `.rtf` / `.odt`, and `OOXMLArchive` — a small ZIP reader on the Compression framework — with `XMLParser` walkers (`OOXMLText`) for `.docx` paragraphs and tables, `.xlsx` sheets as Markdown tables, and `.pptx` slides with notes. Text is capped per file and per message; the flag survives on the attachment so the UI can say so. Files arrive through the composer's paperclip, a Finder drop on the field, or ⌘V of a file URL (`ComposerTextView`).

`AttachmentPrompt` renders every non-image attachment as text shared by both backends. The Responses client sends images as `input_image`, PDFs natively as `input_file`, and the rest as an `input_text` part ahead of the user's words; Codex gets the same text (PDF text included) in the prompt and images by path via `--image`.

## Mentions and citations

Typing `@` anywhere in the draft opens the same picker as `/` (`ComposerPickerPanel`, generic over `ComposerPickable`) listing `ComposerTool` — `web_search` today. Picking one attaches a `.tool` chip with no payload; `AttachmentPrompt` and the Responses input skip it, and `AppSession.makeStream` reads it: `ChatContinuation.webSearch` is the global setting **or** an `@web_search` chip on the newest user message, and only then does the request carry `tools: [web_search]` and the search hint in `instructions`. Codex chats get a "use web search" line in the prompt instead.

`ResponsesClient` turns `response.output_text.annotation.added` events of type `url_citation` into `ChatStreamEvent.citation`, deduped by URL per response, and backfills from the completed response's `output[].content[].annotations`. Citations are stored on the message (`citationsJSON`) and drawn by `CitationRow` as numbered host + title chips under the answer (five, then "+N"); clicking opens the page and Copy appends a Sources list.

## Skills

A skill is Markdown in `~/.cue/skills/` (`name.md` or `name/SKILL.md`, optional front matter with `name:` / `description:`); a project with a code folder also contributes `.cue/skills` and `.claude/skills` from that folder, overriding global names. `SkillCatalog` loads and parses; `SkillLibrary` (MainActor) keeps the list current with a vnode source on the global folder and reloads when the workspace changes. Typing `/` at the start of the draft opens `SkillPickerPanel` above the composer; the field forwards arrows / Return / Tab / Escape to it. Picking a skill attaches it as a `.skill` chip with the body captured at that moment, so history stays stable if the file changes later.

## Projects

A `Project` is a workspace: name, optional instructions, knowledge files, and grouped chats. Knowledge is `[MessageAttachment]` with payloads stripped (PDFs keep their extracted text), built with the same importer. `ProjectContext.promptBlock()` renders instructions and knowledge; personal chats append it to the Responses `instructions` on every turn (the API does not carry instructions across `previous_response_id`; `prompt_cache_key` keeps the repeated prefix cheap), and Codex chats get it at the top of the prompt. The sidebar's Projects section filters chats by `selectedProjectID` and new chats land in the selected workspace; `ProjectSettingsView` edits everything in place.

### Code mode

Linking a code folder to a project switches its chats to Codex. Conversations carry `projectID`; turns in a folder-linked project spawn `codex exec --experimental-json --sandbox read-only --cd <folder> --skip-git-repo-check` with `CODEX_API_KEY` from the Keychain, write the newest user message to stdin, and map the JSONL thread events onto `ChatStreamEvent` (`CodexEventMapper`). The thread id from `thread.started` is stored on the conversation and passed as `resume <id>` on follow-ups. Optional indexing builds a map catalog (`ProjectCatalog`) that is prepended to the prompt.

`CodexBinaryLocator` finds the CLI: the Settings override, a bundled auxiliary executable, PATH and common prefixes, global npm packages (unwrapping the JS shim to the vendored Mach-O), then the copy inside Halo.app. `ProjectPaths` refuses filesystem roots and OS directories as a working directory.

## Listen

One `ListenController` fans out to three sources. Whisper and Speech share ScreenCaptureKit system audio, an energy VAD, and a ring buffer. Accessibility ports AirScript: dedicated AX thread, `AXObserver`, adaptive 10 Hz → 1 Hz poll, cached nodes, caption merge.

Listen output has two consumers. The composer draft gets it as before (Whisper/Speech append a segment; Accessibility syncs the caption snapshot through `CaptionDraftSync`), unless **Settings → Listen → Insert speech into the draft** is off. `TranscriptLog` (`Captions/`) is the other: a capped, session-long log that survives `resetAfterSend`. Whisper/Speech append a committed line per segment; the Accessibility path mirrors `CaptionLineAssembler`'s rows by id, so the live row updates in place and rows the assembler drops after its own reset stay as history. `TranscriptStrip` sits above the composer while listen is armed or anything has been heard: the last three lines, the whole log on disclosure, a row click quotes the line into the draft, and **Answer** sends the latest sentence. Hotkeys `answerLastSentence` / `answerRecent` / `answerAll` (⌘num1 / num3 / num0) call `AppSession.answerFromTranscript(sentences:)`, which parks whatever was typed, sends the grabbed sentences (`CaptionSentenceGrab`) with the current attachments, restores the typed draft, and moves the log's answered watermark — `answerAll` only sends what came after it.

## Remote control

One session-level `CGEvent` tap (`RemoteInputTap`) owns input while remote mode is on. Pointer motion passes through and its `mouseEventDeltaX/Y` move a virtual cursor in panel content space (origin top-left, so it matches SwiftUI and keeps tracking when the real cursor hits a screen edge). Clicks, wheel, and keys are swallowed and replayed into the Cue panel as synthetic `NSEvent`s at the cursor (`CuePanelController.replay`), typing goes to the composer draft via `keyboardGetUnicodeString`, and ⌘V pastes text or an image. A fullscreen transparent shield sits under the real cursor as a backstop for anything the tap misses. `CuePanel.allowsKeyStatus` is off during remote so a replayed click can never make Cue key. Escape or the hotkey exits; Force Quit (`⌘⌥Esc`) is never consumed.
