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

## Listen + remote

Listen controls live in the composer tools row. Remote mode draws a virtual cursor overlay; it must not restyle the rest of the chrome.
