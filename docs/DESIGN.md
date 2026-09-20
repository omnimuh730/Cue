# Cue design

Cue should feel like Tahoe glass sitting on the desktop: strong refraction, compact chrome, and a calm reading column.

## Character

1. Preserve the reading column and composer before adding controls.
2. Prefer spacing, alignment, and type weight over extra containers.
3. Persistent chrome stays compact; secondary actions appear on hover or focus.
4. One clear primary action per surface (composer send).
5. Every control has hover, focus, disabled, and error behavior where it applies.

## Glass

Use Liquid Glass for floating surfaces:

- Sidebar, composer, settings, search, thread info, model popover
- `glassEffect` / `NSGlassEffectView` with a hairline stroke
- Window is a transparent `NSPanel`; content provides the material
- If Reduce Transparency is on, use opaque `windowBackgroundColor`

Do not fill the chat canvas with a second glass card. Assistant messages sit on the reading surface.

## Layout

- Sidebar: 282pt desktop, overlay below 680pt
- No header; a 28pt drag strip tops the reading column
- Reading / composer column: 800pt max, shared centerline
- Row radius 8, panels 16, composer 28
- 4pt spacing rhythm: 4, 8, 12, 16, 20, 24, 32

## Type

System UI stack. Body 14, assistant 15.5 / 1.68, user bubble 15 / 1.45, header 15 semibold, empty title 27 medium.

## Color

Semantic only: accent for send/primary, success for armed listen, warning for transcribing, danger for errors. User bubbles use a quiet fill, not a brand color.

## Motion

One vocabulary, `CueMotion`: `panel` for surfaces sliding in (sidebar, pickers, dialogs), `control` for hover and press, `arrive` for a turn landing in the transcript, `fade` for opacity. Everything honors Reduce Motion.

- Buttons dip on press (`CuePressButtonStyle`) and lift a few percent under the pointer; hover-revealed rows rise in rather than pop.
- The composer glass carries a pointer-following sheen. The sidebar does not.
- The orb (`CueOrb`) is Cue's presence while it works: a sphere of drifting pastel light — a Metal aurora field under native specular, shadow, rim, and halo — as the busy indicator everywhere (thinking row, streaming tail, sidebar, pills). The app mark stays in the menu bar only.
- The empty chat's hero is the word CUE written in ~1,900 star particles (`ParticleWordView`, SpriteKit sprites with hand-rolled physics): they fly in from a spiral, settle into the glyphs on springs, drift on small loops under a slow wave so the shape lives without breaking, and scatter from the pointer before springing home. Starlight (additive white / ice / peach) on dark glass, jewel tints on light. It is the title; nothing repeats it.
- While a reply streams, the composer's edge glows with the same aurora light (`cueAuroraGlow`), a one-pass distance-field shader — never a blur.
- Cost: every continuous effect reads `cueMotionActive` and stops when the panel is hidden or covered or Reduce Motion is on. Orbs, glow, and shimmer run at 30 fps; the particle field at 60 only while the pointer is in it. Shaders are compiled at launch off the main thread. Nothing in the chrome blurs per frame.
- Buttons are flat fills. The send / stop disc answers the pointer with a tinted glow and a lift, never a gradient. Inline text actions use `CueInlineButtonStyle` (a quiet capsule).
- Settings: the pane list's selection pill slides between rows; each pane rises in under a title and one-line subtitle; the card itself rises onto the scrim.
- Metal is used only for light: `cueAurora`, `cueShimmer` (the "Thinking…" sweep), `cueSparkle` (the send disc as a draft becomes sendable). Particles are SpriteKit. No 3D, no third-party animation runtimes.

## Listen + remote

Listen controls live in the composer tools row. Remote mode draws a virtual cursor overlay; it must not restyle the rest of the chrome.
