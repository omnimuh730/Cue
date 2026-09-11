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
