import AppKit
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: AppSession?
    private var panel: CuePanelController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let schema = Schema([Conversation.self, Message.self, Project.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        let session = AppSession(container: container, settingsStore: SettingsStore())
        let root = RootView(session: session)
        let panel = CuePanelController(rootView: root)
        panel.onClose = { }
        session.attach(panel: panel)
        panel.apply(settings: session.settings, remoteActive: false)
        panel.reveal(passive: session.settings.passiveFocusMode)
        self.session = session
        self.panel = panel

        NotificationCenter.default.addObserver(forName: .cueToggleWindow, object: nil, queue: .main) { _ in
            Task { @MainActor in
                session.handle(.toggleShowHide)
            }
        }
        NotificationCenter.default.addObserver(forName: .cueOpenSettings, object: nil, queue: .main) { _ in
            Task { @MainActor in
                session.settingsOpen = true
                session.panel?.reveal(passive: session.settings.passiveFocusMode)
            }
        }
        NotificationCenter.default.addObserver(forName: .cueQuit, object: nil, queue: .main) { _ in
            Task { @MainActor in
                session.quit()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        session?.handle(.toggleShowHide)
        return false
    }
}
