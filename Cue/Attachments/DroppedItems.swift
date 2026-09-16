import AppKit
import Foundation
import UniformTypeIdentifiers

/// Resolves what a drag brought in: files from Finder, or image data from an app that drags
/// pixels rather than a path (a browser, Photos, a screenshot thumbnail).
nonisolated enum DroppedItems {
    static let acceptedTypes: [UTType] = [.fileURL, .image]

    struct Payload: Sendable {
        var urls: [URL] = []
        var images: [Data] = []
        var isEmpty: Bool { urls.isEmpty && images.isEmpty }
    }

    static func load(_ providers: [NSItemProvider]) async -> Payload {
        var payload = Payload()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await fileURL(from: provider) {
                    payload.urls.append(url)
                    continue
                }
            }
            if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
               let data = await data(from: provider, type: type) {
                payload.images.append(data)
            }
        }
        return payload
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func data(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
