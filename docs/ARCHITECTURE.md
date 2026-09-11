# Cue architecture

```text
SwiftUI (glass UI)
  └─ NSPanel (nonactivating, stealth, opacity)
       ├─ AppSession (MainActor)
       │    ├─ SwiftData conversations
       │    ├─ Keychain API key
       │    └─ URLSession Responses client
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

## Listen

One `ListenController` fans out to three sources. Whisper and Speech share ScreenCaptureKit system audio, an energy VAD, and a ring buffer. Accessibility ports AirScript: dedicated AX thread, `AXObserver`, adaptive 10 Hz → 1 Hz poll, cached nodes, caption merge.

## Remote control

A fullscreen transparent shield swallows mouse hits. Relative mouse deltas move a virtual cursor inside Cue. A `CGEvent` keyboard tap swallows typing and paste and applies them in the composer without transferring OS focus. Force Quit (`⌘⌥Esc`) is never consumed.
