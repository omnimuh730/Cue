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

Streaming is paced, not per token: deltas are batched into the model at 25 fps and SwiftData is committed at most once a second while a turn runs (and at turn end). `ChatView` iterates `Message` objects, so a delta re-renders only its bubble. Assistant Markdown is split into paragraph / heading / code / Mermaid blocks by `MarkdownRenderer`, which parses inline Markdown off the main thread and reuses already-parsed blocks, so a streaming update costs one trailing block.

Mermaid renders in a `WKWebView` once the turn completes (source while streaming) from a bundled host page (`Resources/Mermaid`, no network; the 3.5 MB library is only loaded for uncached diagrams). Rendered SVG and measured height are cached per source so reopening a chat is instant and never reflows. Mermaid's DOMPurify pass drops the root `<svg id>` under WebKit, which orphans its scoped stylesheet; the host page re-applies the id after injection. Zoom is the web view's native page magnification (`MermaidWebContentView`): pinch and smart-zoom are native, ⌘-scroll zooms toward the cursor, scroll or drag pans via `window.scrollBy` while zoomed, double-click resets, and unzoomed scrolls are passed up so the chat scrolls through diagrams.

There is no title bar: the sidebar row's info button opens `ThreadInfoView` (cost, tokens with prompt-cache share, latency, per-reply breakdown). Personal turns send a per-thread `prompt_cache_key` so OpenAI serves the shared prefix from cache.

## Projects (Code mode)

A project is a local folder opened from the sidebar workspace switcher. Conversations carry `projectID`; turns in a project workspace spawn `codex exec --experimental-json --sandbox read-only --cd <folder> --skip-git-repo-check` with `CODEX_API_KEY` from the Keychain, write the newest user message to stdin, and map the JSONL thread events onto `ChatStreamEvent` (`CodexEventMapper`). The thread id from `thread.started` is stored on the conversation and passed as `resume <id>` on follow-ups. Optional indexing builds a map catalog (`ProjectCatalog`) that is prepended to the prompt.

`CodexBinaryLocator` finds the CLI: the Settings override, a bundled auxiliary executable, PATH and common prefixes, global npm packages (unwrapping the JS shim to the vendored Mach-O), then the copy inside Halo.app. `ProjectPaths` refuses filesystem roots and OS directories as a working directory.

## Listen

One `ListenController` fans out to three sources. Whisper and Speech share ScreenCaptureKit system audio, an energy VAD, and a ring buffer. Accessibility ports AirScript: dedicated AX thread, `AXObserver`, adaptive 10 Hz → 1 Hz poll, cached nodes, caption merge.

## Remote control

One session-level `CGEvent` tap (`RemoteInputTap`) owns input while remote mode is on. Pointer motion passes through and its `mouseEventDeltaX/Y` move a virtual cursor in panel content space (origin top-left, so it matches SwiftUI and keeps tracking when the real cursor hits a screen edge). Clicks, wheel, and keys are swallowed and replayed into the Cue panel as synthetic `NSEvent`s at the cursor (`CuePanelController.replay`), typing goes to the composer draft via `keyboardGetUnicodeString`, and ⌘V pastes text or an image. A fullscreen transparent shield sits under the real cursor as a backstop for anything the tap misses. `CuePanel.allowsKeyStatus` is off during remote so a replayed click can never make Cue key. Escape or the hotkey exits; Force Quit (`⌘⌥Esc`) is never consumed.
