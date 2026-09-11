import Foundation

nonisolated struct RectValue: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated enum WindowBounds {
    static let nudgeStep: Double = 40
    static let minWidth: Double = 420
    static let minHeight: Double = 420

    static func clampMovedBounds(_ bounds: RectValue, workArea: RectValue, dx: Double, dy: Double) -> RectValue {
        let width = max(1, bounds.width)
        let height = max(1, bounds.height)
        var x = bounds.x + dx
        var y = bounds.y + dy
        let maxX = workArea.x + workArea.width - width
        let maxY = workArea.y + workArea.height - height
        if maxX >= workArea.x { x = min(max(x, workArea.x), maxX) }
        if maxY >= workArea.y { y = min(max(y, workArea.y), maxY) }
        return RectValue(x: x, y: y, width: width, height: height)
    }

    static func clampResizedBounds(
        _ bounds: RectValue,
        workArea: RectValue,
        dw: Double,
        dh: Double,
        minWidth: Double = minWidth,
        minHeight: Double = minHeight
    ) -> RectValue {
        let maxWidth = max(minWidth, workArea.x + workArea.width - bounds.x)
        let maxHeight = max(minHeight, workArea.y + workArea.height - bounds.y)
        let width = min(max(bounds.width + dw, minWidth), maxWidth)
        let height = min(max(bounds.height + dh, minHeight), maxHeight)
        return RectValue(x: bounds.x, y: bounds.y, width: width, height: height)
    }
}
