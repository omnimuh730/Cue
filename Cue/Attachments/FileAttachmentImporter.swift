import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

nonisolated enum AttachmentImportError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupported(String)
    case tooLarge(String, limitMB: Int)
    case tooManyPages(String, pages: Int)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Could not read \(name)."
        case .unsupported(let name): "\(name) is not a supported file type. Use PDF, Word, Excel, PowerPoint, images, or text files."
        case .tooLarge(let name, let limit): "\(name) is larger than \(limit) MB."
        case .tooManyPages(let name, let pages): "\(name) has \(pages) pages; PDFs are limited to \(FileAttachmentImporter.maxPDFPages)."
        case .empty(let name): "No text could be extracted from \(name)."
        }
    }
}

/// Turns a file on disk into a `MessageAttachment` using only Apple frameworks: PDFKit for PDFs,
/// AppKit's text importers for legacy Word / RTF / OpenDocument, and `OOXMLArchive` for the
/// Office Open XML formats. Runs off the main actor; nothing here touches UI.
nonisolated enum FileAttachmentImporter {
    static let maxTextCharacters = 300_000
    static let maxMessageTextCharacters = 600_000
    static let maxPDFBytes = 20 * 1024 * 1024
    static let maxPDFPages = 100
    static let maxTextFileBytes = 8 * 1024 * 1024
    static let maxImageDimension: CGFloat = 2_048

    static let officeOpenXMLTypes: [UTType] = [
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("org.openxmlformats.spreadsheetml.sheet"),
        UTType("org.openxmlformats.presentationml.presentation")
    ].compactMap { $0 }

    static let legacyDocumentTypes: [UTType] = [
        UTType("com.microsoft.word.doc"),
        UTType.rtf,
        UTType("org.oasis-open.opendocument.text")
    ].compactMap { $0 }

    /// Types offered by the open panel and accepted on drop.
    static var allowedContentTypes: [UTType] {
        [.pdf, .image, .text, .sourceCode, .json, .yaml, .xml, .commaSeparatedText, .tabSeparatedText, .plainText]
            + officeOpenXMLTypes + legacyDocumentTypes
            + [UTType("net.daringfireball.markdown")].compactMap { $0 }
    }

    /// Extensions that ship without a registered text UTType but are plain text in practice.
    static let textExtensions: Set<String> = [
        "md", "mdc", "mdx", "markdown", "txt", "text", "csv", "tsv", "json", "jsonl", "yaml", "yml", "toml", "ini",
        "cfg", "conf", "env", "log", "xml", "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "go", "py", "rb", "php", "java", "kt", "kts",
        "scala", "sh", "zsh", "bash", "fish", "ps1", "sql", "graphql", "gql", "proto", "r", "lua", "dart", "ex",
        "exs", "erl", "hs", "ml", "clj", "vue", "svelte", "tex", "rst", "adoc", "org", "diff", "patch", "gitignore",
        "dockerfile", "makefile", "plist", "strings", "xcconfig", "pbxproj", "cue"
    ]

    static func load(_ url: URL) throws -> MessageAttachment {
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        let ext = url.pathExtension.lowercased()

        if let type, type.conforms(to: .image) {
            return try loadImage(url, name: name, type: type)
        }
        if type?.conforms(to: .pdf) == true || ext == "pdf" {
            return try loadPDF(url, name: name)
        }
        switch ext {
        case "docx": return try loadOOXML(url, name: name, mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", extract: OOXMLText.docx)
        case "xlsx", "xlsm": return try loadOOXML(url, name: name, mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", extract: OOXMLText.xlsx)
        case "pptx": return try loadOOXML(url, name: name, mimeType: "application/vnd.openxmlformats-officedocument.presentationml.presentation", extract: OOXMLText.pptx)
        case "doc": return try loadAttributed(url, name: name, documentType: .docFormat, mimeType: "application/msword")
        case "rtf": return try loadAttributed(url, name: name, documentType: .rtf, mimeType: "text/rtf")
        case "odt": return try loadAttributed(url, name: name, documentType: .openDocument, mimeType: "application/vnd.oasis.opendocument.text")
        case "xls", "ppt":
            throw AttachmentImportError.unsupported(name)
        default:
            break
        }
        if isTextLike(type: type, extension: ext, name: name) {
            return try loadText(url, name: name, mimeType: type?.preferredMIMEType ?? "text/plain")
        }
        // Unknown extension: accept it if the bytes are valid UTF-8 text.
        if let data = try? readData(url, name: name, limit: maxTextFileBytes), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return makeText(text, name: name, mimeType: "text/plain", kind: .text, byteCount: data.count)
        }
        throw AttachmentImportError.unsupported(name)
    }

    static func isTextLike(type: UTType?, extension ext: String, name: String) -> Bool {
        if let type, type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .yaml) || type.conforms(to: .xml) {
            return true
        }
        if textExtensions.contains(ext) { return true }
        let lowered = name.lowercased()
        return ["dockerfile", "makefile", "readme", "license", "agents.md", "claude.md"].contains(lowered)
    }

    // MARK: - Loaders

    private static func loadImage(_ url: URL, name: String, type: UTType) throws -> MessageAttachment {
        guard let image = NSImage(contentsOf: url) else { throw AttachmentImportError.unreadable(name) }
        guard let dataURL = ImageAttachmentEncoder.jpegDataURL(image, maxDimension: maxImageDimension) else {
            throw AttachmentImportError.unreadable(name)
        }
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return MessageAttachment(kind: .image, mimeType: "image/jpeg", name: name, dataURL: dataURL, byteCount: byteCount)
    }

    private static func loadPDF(_ url: URL, name: String) throws -> MessageAttachment {
        let data = try readData(url, name: name, limit: maxPDFBytes)
        guard let document = PDFDocument(data: data) else { throw AttachmentImportError.unreadable(name) }
        guard document.pageCount <= maxPDFPages else {
            throw AttachmentImportError.tooManyPages(name, pages: document.pageCount)
        }
        let text = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let (clipped, truncated) = clip(text)
        return MessageAttachment(
            kind: .pdf,
            mimeType: "application/pdf",
            name: name,
            dataURL: "data:application/pdf;base64,\(data.base64EncodedString())",
            text: clipped,
            byteCount: data.count,
            truncated: truncated
        )
    }

    private static func loadOOXML(_ url: URL, name: String, mimeType: String, extract: (OOXMLArchive) throws -> String) throws -> MessageAttachment {
        let data = try readData(url, name: name, limit: maxPDFBytes)
        let archive: OOXMLArchive
        do {
            archive = try OOXMLArchive(data: data)
        } catch {
            throw AttachmentImportError.unreadable(name)
        }
        let text: String
        do {
            text = try extract(archive)
        } catch {
            throw AttachmentImportError.unreadable(name)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AttachmentImportError.empty(name) }
        return makeText(text, name: name, mimeType: mimeType, kind: .document, byteCount: data.count)
    }

    private static func loadAttributed(_ url: URL, name: String, documentType: NSAttributedString.DocumentType, mimeType: String) throws -> MessageAttachment {
        let data = try readData(url, name: name, limit: maxPDFBytes)
        guard let attributed = try? NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil) else {
            throw AttachmentImportError.unreadable(name)
        }
        let text = attributed.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AttachmentImportError.empty(name) }
        return makeText(text, name: name, mimeType: mimeType, kind: .document, byteCount: data.count)
    }

    private static func loadText(_ url: URL, name: String, mimeType: String) throws -> MessageAttachment {
        let data = try readData(url, name: name, limit: maxTextFileBytes)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AttachmentImportError.unreadable(name)
        }
        return makeText(text, name: name, mimeType: mimeType, kind: .text, byteCount: data.count)
    }

    // MARK: - Helpers

    private static func readData(_ url: URL, name: String, limit: Int) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw AttachmentImportError.tooLarge(name, limitMB: limit / (1024 * 1024)) }
        guard let data = try? Data(contentsOf: url) else { throw AttachmentImportError.unreadable(name) }
        return data
    }

    static func makeText(_ text: String, name: String, mimeType: String, kind: AttachmentKind, byteCount: Int) -> MessageAttachment {
        let (clipped, truncated) = clip(text)
        return MessageAttachment(kind: kind, mimeType: mimeType, name: name, text: clipped, byteCount: byteCount, truncated: truncated)
    }

    static func clip(_ text: String, limit: Int = maxTextCharacters) -> (String, Bool) {
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)) + "\n\n[truncated: file continues beyond \(limit) characters]", true)
    }
}

/// JPEG encoding shared by screenshots, pasted images, and imported image files.
nonisolated enum ImageAttachmentEncoder {
    static let compression: CGFloat = 0.82

    static func jpegDataURL(_ image: NSImage, maxDimension: CGFloat? = nil) -> String? {
        guard var cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        if let maxDimension {
            let longest = CGFloat(max(cgImage.width, cgImage.height))
            if longest > maxDimension, let scaled = downscale(cgImage, by: maxDimension / longest) {
                cgImage = scaled
            }
        }
        return jpegDataURL(cgImage)
    }

    static func jpegDataURL(_ image: CGImage) -> String? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression]) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    private static func downscale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
