# Agent guidance

Follow `.cursor/rules/` on every change.

- Visual contract: `docs/DESIGN.md` and `.cursor/rules/design-philosophy.mdc`
- Swift practice: `.cursor/rules/swift-practice.mdc`
- Native APIs only: `.cursor/rules/native-os.mdc`
- Product scope: `.cursor/rules/halo-parity.mdc` and `docs/ARCHITECTURE.md`

`Halo/` and `AirScript/` are read-only references. Implement features in `Cue/` with macOS frameworks. Do not copy Electron renderer patterns into SwiftUI.
