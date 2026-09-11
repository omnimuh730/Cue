import SwiftData
import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cue", systemImage: CueTheme.symbolName) {
            Button("Show / Hide Cue") {
                NotificationCenter.default.post(name: .cueToggleWindow, object: nil)
            }
            Button("Settings…") {
                NotificationCenter.default.post(name: .cueOpenSettings, object: nil)
            }
            Divider()
            Button("Quit Cue") {
                NotificationCenter.default.post(name: .cueQuit, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let cueToggleWindow = Notification.Name("cue.toggleWindow")
    static let cueOpenSettings = Notification.Name("cue.openSettings")
    static let cueQuit = Notification.Name("cue.quit")
}
