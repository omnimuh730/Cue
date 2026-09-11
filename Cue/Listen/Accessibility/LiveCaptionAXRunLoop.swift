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

    func perform(_ work: @escaping () -> Void) {
        guard let runLoop = cfRunLoop else { return }
        if isOnAXThread {
            work()
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    func performSync<T>(_ work: () -> T) -> T {
        if isOnAXThread {
            return work()
        }
        guard cfRunLoop != nil else {
            return work()
        }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        withoutActuallyEscaping(work) { escapingWork in
            perform {
                result = escapingWork()
                done.signal()
            }
            done.wait()
        }
        return result ?? work()
    }
}
