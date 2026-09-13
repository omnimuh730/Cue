import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotCapture {
    var dataURL: String
    var name: String
    var mimeType: String
}

enum ScreenshotService {
    static func captureDesktop(excluding window: NSWindow?) async throws -> ScreenshotCapture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ChatError.transport("No display available for screenshot.")
        }
        var excluded: [SCWindow] = []
        if let window, let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
            excluded = [scWindow]
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try encode(image, name: "desktop-\(timestamp()).jpg")
    }

    static func captureRegion(hiding panel: CuePanelController) async throws -> ScreenshotCapture {
        panel.hide()
        try await Task.sleep(for: .milliseconds(180))
        let url = FileManager.default.temporaryDirectory.appending(path: "cue-region-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        try process.run()
        process.waitUntilExit()
        panel.reveal(passive: true)
        guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else {
            throw ChatError.transport("Region capture cancelled.")
        }
        try? FileManager.default.removeItem(at: url)
        return try encode(image, name: "region-\(timestamp()).jpg")
    }

    private static func encode(_ image: CGImage, name: String) throws -> ScreenshotCapture {
        guard let dataURL = ImageAttachmentEncoder.jpegDataURL(image) else {
            throw ChatError.transport("Could not encode screenshot.")
        }
        return ScreenshotCapture(dataURL: dataURL, name: name, mimeType: "image/jpeg")
    }

    private static func encode(_ image: NSImage, name: String) throws -> ScreenshotCapture {
        guard let dataURL = ImageAttachmentEncoder.jpegDataURL(image) else {
            throw ChatError.transport("Could not encode screenshot.")
        }
        return ScreenshotCapture(dataURL: dataURL, name: name, mimeType: "image/jpeg")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
