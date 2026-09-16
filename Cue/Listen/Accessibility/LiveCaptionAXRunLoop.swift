import Foundation

nonisolated final class LiveCaptionAXRunLoop: @unchecked Sendable {
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var keepAlive: CFRunLoopSource?
    private let lock = NSLock()
    private var stopped: DispatchSemaphore?

    var cfRunLoop: CFRunLoop? {
        lock.lock()
        defer { lock.unlock() }
        return runLoop
    }

    var isOnAXThread: Bool {
        Thread.current === thread
    }

    func start() {
        lock.lock()
        if runLoop != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        self.stopped = stopped
        let thread = Thread { [weak self] in
            guard let self else { return }
            let current = CFRunLoopGetCurrent()
            var context = CFRunLoopSourceContext()
            let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            CFRunLoopAddSource(current, source, .commonModes)
            self.lock.lock()
            self.runLoop = current
            self.keepAlive = source
            self.lock.unlock()
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(current, source, .commonModes)
            self.lock.lock()
            self.runLoop = nil
            self.keepAlive = nil
            self.lock.unlock()
            stopped.signal()
        }
        thread.name = "Cue Live Captions AX"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
        ready.wait()
    }

    func stop() {
        lock.lock()
        let hasLoop = runLoop != nil
        lock.unlock()
        guard hasLoop else {
            thread = nil
            return
        }
        perform {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        _ = stopped?.wait(timeout: .now() + 1)
        thread = nil
        stopped = nil
    }

    /// Queues `work` on the AX thread. Returns `false` when there is no live run loop to take it,
    /// so a caller waiting on the result can fall back instead of waiting forever.
    @discardableResult
    func perform(_ work: @escaping () -> Void) -> Bool {
        guard let runLoop = cfRunLoop else { return false }
        if isOnAXThread {
            work()
            return true
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
        return true
    }

    /// Bound on how long a synchronous hop waits for the AX thread. The loop can be told to stop
    /// between queueing the block and running it, in which case the block is dropped, so a wait
    /// with no bound is a wait with no end.
    static let syncTimeout: DispatchTimeInterval = .seconds(2)

    /// Runs `work` on the AX thread and hands back its result.
    ///
    /// `work` has to be escaping: the run loop holds its own reference to the block, and
    /// releases it some time *after* the block has signalled completion. The earlier
    /// `withoutActuallyEscaping` version tripped the runtime's escape check on exactly that
    /// window, taking the app down whenever listen was toggled off while captions were live.
    func performSync<T>(_ work: @escaping () -> T) -> T {
        if isOnAXThread {
            return work()
        }
        let done = DispatchSemaphore(value: 0)
        let box = SyncResult<T>()
        let queued = perform {
            box.value = work()
            done.signal()
        }
        guard queued, done.wait(timeout: .now() + Self.syncTimeout) == .success, let value = box.value else {
            // No AX thread to run it, or the loop went away first; the work is teardown-safe
            // off the AX thread, and doing it here beats never doing it.
            return work()
        }
        return value
    }
}

/// Mutable slot a block can write into; the semaphore orders the write before the read.
private final class SyncResult<T>: @unchecked Sendable {
    var value: T?
}
