import Foundation
import UniformTypeIdentifiers

/// What a paste into the composer should become.
nonisolated enum PasteboardContent: Equatable, Sendable {
    case files
    case image
    case text
}

/// Decides between the representations a pasteboard offers.
///
/// Copying an image from a browser or Preview puts the pixels *and* a string (the URL, alt text,
/// HTML) on the pasteboard, so "no string means image" misses most real image copies. Copying
/// spreadsheet cells does the reverse: text first, with a rendered picture of the cells behind it.
/// The source app lists its preferred representation first, so that order is the tie-breaker.
nonisolated enum PasteboardIntent {
    static func classify(types: [String], hasFiles: Bool, hasString: Bool) -> PasteboardContent {
        if hasFiles { return .files }
        let hasImage = types.contains(where: isImage)
        guard hasImage else { return .text }
        guard hasString else { return .image }
        return types.first.map(isImage) == true ? .image : .text
    }

    static func isImage(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .image)
    }
}
