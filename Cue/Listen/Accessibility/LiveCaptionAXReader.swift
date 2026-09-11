import ApplicationServices
import Foundation

nonisolated final class LiveCaptionAXReader: @unchecked Sendable {
    private var cachedPID: pid_t?
    private var textElements: [AXUIElement] = []
    private var windows: [AXUIElement] = []
    private var windowChildCounts: [Int] = []
    private var pollsSinceFullWalk = 0

    func invalidate() {
        cachedPID = nil
        textElements = []
        windows = []
        windowChildCounts = []
        pollsSinceFullWalk = 0
    }

    var observedWindows: [AXUIElement] { windows }

    func snapshot(pid: pid_t, forceFullWalk: Bool) -> String {
        if cachedPID != pid {
            invalidate()
            cachedPID = pid
        }

        let preferCached = !forceFullWalk
            && !textElements.isEmpty
            && pollsSinceFullWalk < CaptionPollCadence.fullWalkEveryActivePolls

        if preferCached, windowShapeStillMatches(pid: pid), let cached = readCachedElements() {
            pollsSinceFullWalk += 1
            return cached
        }

        return fullWalk(pid: pid)
    }

    private func windowShapeStillMatches(pid: pid_t) -> Bool {
        guard let counts = childCounts(pid: pid) else { return false }
        return counts == windowChildCounts
    }

    private func readCachedElements() -> String? {
        var lines: [String] = []
        var failures = 0
        for element in textElements {
            guard let value = string(element, kAXValueAttribute as String)
                ?? string(element, kAXDescriptionAttribute as String)
            else {
                failures += 1
                continue
            }
            appendCaptionLines(from: value, into: &lines)
        }
        if !textElements.isEmpty, failures == textElements.count {
            return nil
        }
        return CaptionTextMerge.collapse(lines).joined(separator: "\n")
    }

    private func fullWalk(pid: pid_t) -> String {
        pollsSinceFullWalk = 0
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)

        let windowList = attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
        windows = windowList
        windowChildCounts = windowList.map { children($0).count }

        var lines: [String] = []
        var elements: [AXUIElement] = []
        if windowList.isEmpty {
            collect(from: app, into: &lines, elements: &elements, depth: 0)
        } else {
            for window in windowList {
                collect(from: window, into: &lines, elements: &elements, depth: 0)
            }
        }
        textElements = elements
        return CaptionTextMerge.collapse(lines).joined(separator: "\n")
    }

    private func childCounts(pid: pid_t) -> [Int]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let windowList = attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return nil
        }
        return windowList.map { children($0).count }
    }

    private func collect(
        from element: AXUIElement,
        into lines: inout [String],
        elements: inout [AXUIElement],
        depth: Int
    ) {
        guard depth < 12, lines.count < 40 else { return }
        let role = string(element, kAXRoleAttribute as String) ?? ""
        if role.contains("Menu") { return }

        if let value = string(element, kAXValueAttribute as String)
            ?? string(element, kAXDescriptionAttribute as String),
           !value.isEmpty {
            let before = lines.count
            appendCaptionLines(from: value, into: &lines)
            if lines.count > before {
                elements.append(element)
            }
        }

        for child in children(element) {
            collect(from: child, into: &lines, elements: &elements, depth: depth + 1)
        }
    }

    private func appendCaptionLines(from value: String, into lines: inout [String]) {
        for line in value.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
        where !line.isEmpty && !CaptionTextMerge.isChrome(line) && !lines.contains(line) {
            lines.append(line)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let string = attribute(element, name) as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }
}
