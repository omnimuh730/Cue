import Foundation

nonisolated struct RemoteCursorDelta: Equatable, Sendable {
    var virtualX: Double
    var virtualY: Double
    var lastScreenX: Double
    var lastScreenY: Double
    var moved: Bool
}

nonisolated enum RemoteCursorMath {
    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(max, Swift.max(min, value))
    }

    /// Moves the virtual cursor by a relative delta in content space (origin top-left, +y down),
    /// clamped to the panel. Used with CGEvent `mouseEventDeltaX/Y`, which keep reporting motion
    /// even while the real cursor is pinned against a screen edge.
    static func applyDelta(
        virtualX: Double,
        virtualY: Double,
        dx: Double,
        dy: Double,
        width: Double,
        height: Double,
        maxJump: Double = 1600
    ) -> RemoteCursorDelta {
        guard dx != 0 || dy != 0, abs(dx) <= maxJump, abs(dy) <= maxJump else {
            return RemoteCursorDelta(virtualX: virtualX, virtualY: virtualY, lastScreenX: 0, lastScreenY: 0, moved: false)
        }
        let nextX = clamp(virtualX + dx, min: 0, max: Swift.max(0, width - 1))
        let nextY = clamp(virtualY + dy, min: 0, max: Swift.max(0, height - 1))
        return RemoteCursorDelta(
            virtualX: nextX,
            virtualY: nextY,
            lastScreenX: 0,
            lastScreenY: 0,
            moved: nextX != virtualX || nextY != virtualY
        )
    }

    static func applyScreenDelta(
        virtualX: Double,
        virtualY: Double,
        lastScreenX: Double,
        lastScreenY: Double,
        screenX: Double,
        screenY: Double,
        width: Double,
        height: Double,
        maxJump: Double = 1600
    ) -> RemoteCursorDelta {
        let dx = screenX - lastScreenX
        let dy = screenY - lastScreenY
        if dx == 0, dy == 0 {
            return RemoteCursorDelta(
                virtualX: virtualX,
                virtualY: virtualY,
                lastScreenX: screenX,
                lastScreenY: screenY,
                moved: false
            )
        }
        if abs(dx) > maxJump || abs(dy) > maxJump {
            return RemoteCursorDelta(
                virtualX: virtualX,
                virtualY: virtualY,
                lastScreenX: screenX,
                lastScreenY: screenY,
                moved: false
            )
        }
        let maxX = Swift.max(0, width - 1)
        let maxY = Swift.max(0, height - 1)
        let nextX = clamp(virtualX + dx, min: 0, max: maxX)
        let nextY = clamp(virtualY + dy, min: 0, max: maxY)
        return RemoteCursorDelta(
            virtualX: nextX,
            virtualY: nextY,
            lastScreenX: screenX,
            lastScreenY: screenY,
            moved: nextX != virtualX || nextY != virtualY
        )
    }
}
