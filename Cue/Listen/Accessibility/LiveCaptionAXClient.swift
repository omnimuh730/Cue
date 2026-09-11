import ApplicationServices
import Foundation

nonisolated final class LiveCaptionAXClient: @unchecked Sendable {
    private let ax = LiveCaptionAXRunLoop()
    private let reader = LiveCaptionAXReader()
    private let processMonitor = LiveCaptionsProcessMonitor()
    private var cadence = CaptionPollCadence()
    private var pollTimer: CFRunLoopTimer?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var registeredWindowCount = 0
    private var lastText = ""
    private var generation: UInt64 = 0
    private let generationLock = NSLock()
    private var nextPollFullWalk = false
    private var isPolling = false
    private var pollQueued = false
    private var onText: ((String) -> Void)?
    var onRunningChange: (() -> Void)?

    deinit {
        stop()
    }

    var isProcessRunning: Bool { processMonitor.isRunning }

    func start(onText: @escaping (String) -> Void) {
        stop()
        self.onText = onText
        bumpGeneration()
        ax.start()
        processMonitor.onChange = { [weak self] pid in
            self?.ax.perform {
                self?.handleProcessChange(pid)
            }
            DispatchQueue.main.async {
                self?.onRunningChange?()
            }
        }
        processMonitor.start()
        ax.perform { [weak self] in
            self?.handleProcessChange(self?.processMonitor.pid)
            self?.runPoll()
        }
    }

    func stop() {
        bumpGeneration()
        onText = nil
        onRunningChange = nil
        processMonitor.stop()
        ax.performSync { [self] in
            tearDownObserver()
            tearDownTimer()
            reader.invalidate()
            lastText = ""
            cadence = CaptionPollCadence()
            nextPollFullWalk = false
            isPolling = false
            pollQueued = false
        }
        ax.stop()
    }

    fileprivate func wakePoll(forceFullWalk: Bool) {
        if forceFullWalk {
            nextPollFullWalk = true
        }
        cadence.resetToSpeaking()
        applyTimerInterval()
        runPoll()
    }

    private func handleProcessChange(_ pid: pid_t?) {
        if pid == nil || pid != observedPID {
            tearDownObserver()
            reader.invalidate()
            lastText = ""
            observedPID = pid
        }
        guard pid != nil else {
            tearDownTimer()
            return
        }
        cadence.resetToSpeaking()
        installObserverIfNeeded()
        applyTimerInterval()
        runPoll()
    }

    private func runPoll() {
        if isPolling {
            pollQueued = true
            return
        }
        isPolling = true
        poll()
        isPolling = false
        if pollQueued {
            pollQueued = false
            runPoll()
        }
    }

    private func poll() {
        guard let pid = processMonitor.pid else { return }
        let force = nextPollFullWalk
        nextPollFullWalk = false
        let text = reader.snapshot(pid: pid, forceFullWalk: force)
        installObserverIfNeeded()

        let changed = text != lastText
        if changed {
            lastText = text
            cadence.noteChange()
        } else {
            cadence.noteUnchanged()
        }
        applyTimerInterval()
        guard changed, !text.isEmpty else { return }
        let generation = currentGeneration()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration() == generation else { return }
            self.onText?(text)
        }
    }

    private func applyTimerInterval() {
        let interval = cadence.interval
        if let pollTimer, abs(CFRunLoopTimerGetInterval(pollTimer) - interval) < 0.001 {
            return
        }
        tearDownTimer()
        guard let runLoop = ax.cfRunLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + interval,
            interval,
            0,
            0
        ) { [weak self] _ in
            self?.runPoll()
        }
        pollTimer = timer
        CFRunLoopAddTimer(runLoop, timer, .commonModes)
    }

    private func installObserverIfNeeded() {
        guard let pid = processMonitor.pid else { return }
        if observer != nil, observedPID == pid {
            if reader.observedWindows.count != registeredWindowCount {
                registerObserverTargets()
            }
            return
        }
        tearDownObserver()
        var created: AXObserver?
        let result = AXObserverCreate(pid, Self.observerCallback, &created)
        guard result == .success, let observer = created else { return }
        self.observer = observer
        observedPID = pid
        if let runLoop = ax.cfRunLoop {
            CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
        }
        registerObserverTargets()
    }

    private func registerObserverTargets() {
        guard let observer, let pid = processMonitor.pid else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        for notification in Self.observerNotifications {
            AXObserverAddNotification(observer, app, notification as CFString, refcon)
        }
        for window in reader.observedWindows {
            for notification in Self.observerNotifications {
                AXObserverAddNotification(observer, window, notification as CFString, refcon)
            }
        }
        registeredWindowCount = reader.observedWindows.count
    }

    private func tearDownObserver() {
        if let observer, let runLoop = ax.cfRunLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
        registeredWindowCount = 0
    }

    private func tearDownTimer() {
        if let pollTimer {
            CFRunLoopTimerInvalidate(pollTimer)
        }
        pollTimer = nil
    }

    private func bumpGeneration() {
        generationLock.lock()
        generation += 1
        generationLock.unlock()
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    private static let observerNotifications = [
        kAXValueChangedNotification,
        kAXTitleChangedNotification,
        kAXUIElementDestroyedNotification,
        kAXLayoutChangedNotification,
    ]

    private static let observerCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let client = Unmanaged<LiveCaptionAXClient>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        let forceFull = name == (kAXUIElementDestroyedNotification as String)
            || name == (kAXLayoutChangedNotification as String)
        client.wakePoll(forceFullWalk: forceFull)
    }
}
