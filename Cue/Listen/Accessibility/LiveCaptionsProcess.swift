import AppKit
import Foundation

nonisolated enum LiveCaptionsProcess {
    static let bundleIdentifier = "com.apple.accessibility.LiveTranscriptionAgent"
    static let localizedName = "Live Captions"

    static func matches(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == bundleIdentifier || app.localizedName == localizedName
    }

    static func runningApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first(where: matches)
    }
}

nonisolated final class LiveCaptionsProcessMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPID: pid_t?
    private var observers: [NSObjectProtocol] = []
    var onChange: ((pid_t?) -> Void)?

    var pid: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return storedPID
    }

    var isRunning: Bool { pid != nil }

    func start() {
        removeObservers()
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = Self.application(from: notification), LiveCaptionsProcess.matches(app) else {
                    return
                }
                self?.update(pid: app.processIdentifier)
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = Self.application(from: notification), LiveCaptionsProcess.matches(app) else {
                    return
                }
                self?.update(pid: nil)
            }
        )
    }

    func stop() {
        removeObservers()
        lock.lock()
        storedPID = nil
        lock.unlock()
        onChange = nil
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
    }

    func refresh() {
        update(pid: LiveCaptionsProcess.runningApplication()?.processIdentifier)
    }

    private func update(pid: pid_t?) {
        lock.lock()
        let changed = storedPID != pid
        storedPID = pid
        lock.unlock()
        guard changed else { return }
        onChange?(pid)
    }

    private static func application(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
