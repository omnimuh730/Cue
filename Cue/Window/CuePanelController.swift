import AppKit
import SwiftUI

/// Nonactivating panel that can be locked out of key status while remote control replays
/// synthetic clicks into it, so the interview app never loses keyboard focus.
@MainActor
final class CuePanel: NSPanel {
    var allowsKeyStatus = true

    override var canBecomeKey: Bool {
        allowsKeyStatus && super.canBecomeKey
    }
}

@MainActor
final class CuePanelController: NSObject, NSWindowDelegate {
    let panel: CuePanel
    private let hostingView: NSHostingView<RootView>
    var isQuitting = false
    var onClose: (() -> Void)?

    init(rootView: RootView) {
        let hosting = NSHostingView(rootView: rootView)
        hostingView = hosting
        let panel = CuePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Cue"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: WindowBounds.minWidth, height: WindowBounds.minHeight)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.contentView = hosting
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.panel = panel
        super.init()
        panel.delegate = self
        Self.centerOnActiveScreen(panel)
    }

    func apply(settings: PublicSettings, remoteActive: Bool) {
        panel.sharingType = settings.stealthMode ? .none : .readOnly
        if !remoteActive {
            panel.level = settings.alwaysOnTop ? .floating : .normal
        }
        panel.alphaValue = CGFloat(settings.windowOpacity)
    }

    /// Size of the SwiftUI root in points; the virtual cursor lives in this space (origin top-left).
    var contentSize: CGSize {
        panel.contentView?.bounds.size ?? panel.frame.size
    }

    /// Delivers a synthetic AppKit event to the view under `point` (top-left origin, content coordinates).
    func replay(_ event: NSEvent) {
        panel.sendEvent(event)
    }

    func replayScroll(_ event: NSEvent, at point: CGPoint) {
        guard let content = panel.contentView else { return }
        let flipped = NSPoint(x: point.x, y: contentSize.height - point.y)
        let target = content.hitTest(content.convert(flipped, from: nil)) ?? content
        target.scrollWheel(with: event)
    }

    func reveal(passive: Bool) {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        if passive {
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle(passive: Bool) {
        if panel.isVisible {
            hide()
        } else {
            reveal(passive: passive)
        }
    }

    func nudge(dx: Double, dy: Double) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let work = screen.visibleFrame
        let frame = panel.frame
        let next = WindowBounds.clampMovedBounds(
            RectValue(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height),
            workArea: RectValue(x: work.origin.x, y: work.origin.y, width: work.width, height: work.height),
            dx: dx,
            dy: dy
        )
        panel.setFrame(NSRect(x: next.x, y: next.y, width: next.width, height: next.height), display: true)
    }

    func resize(dw: Double, dh: Double) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let work = screen.visibleFrame
        let frame = panel.frame
        let next = WindowBounds.clampResizedBounds(
            RectValue(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height),
            workArea: RectValue(x: work.origin.x, y: work.origin.y, width: work.width, height: work.height),
            dw: dw,
            dh: dh
        )
        panel.setFrame(NSRect(x: next.x, y: next.y, width: next.width, height: next.height), display: true)
    }

    func adjustOpacity(_ delta: Double) -> Double {
        let next = min(1, max(0.15, panel.alphaValue + delta))
        panel.alphaValue = next
        return Double(next)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isQuitting { return true }
        hide()
        onClose?()
        return false
    }

    static func centerOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.screens.first { $0.frame.origin.x == 0 }
            ?? NSScreen.main
        guard let screen else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(
            x: area.midX - panel.frame.width / 2,
            y: area.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class StatusItemController {
    private var item: NSStatusItem?
    var onToggle: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: CueTheme.symbolName, accessibilityDescription: "Cue")
            button.image?.isTemplate = true
            button.toolTip = "Cue"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Cue", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cue", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        item.menu = menu
        self.item = item
    }

    @objc private func toggle() { onToggle?() }
    @objc private func settings() { onSettings?() }
    @objc private func quit() { onQuit?() }
}
