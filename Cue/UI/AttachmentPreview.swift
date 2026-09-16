import AppKit
import PDFKit
import SwiftUI

enum AttachmentImage {
    /// Base64 → NSImage is expensive and views ask for the same image on every render, so decode once per attachment id.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func nsImage(from attachment: MessageAttachment) -> NSImage? {
        guard attachment.kind == .image else { return nil }
        let key = attachment.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let payload = attachment.dataURL.split(separator: ",").last,
              let data = Data(base64Encoded: String(payload)),
              let image = NSImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func pdfData(from attachment: MessageAttachment) -> Data? {
        guard attachment.kind == .pdf, let payload = attachment.dataURL.split(separator: ",").last else { return nil }
        return Data(base64Encoded: String(payload))
    }
}

/// Icon, colour, and size label for non-image attachments.
enum AttachmentBadge {
    static func symbol(for attachment: MessageAttachment) -> String {
        switch attachment.kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .skill: "sparkles"
        case .tool: ComposerTool.named(attachment.name)?.symbol ?? "wrench.and.screwdriver"
        case .text: "doc.plaintext"
        case .document:
            if attachment.mimeType.contains("spreadsheet") { "tablecells" }
            else if attachment.mimeType.contains("presentation") { "rectangle.on.rectangle" }
            else { "doc.text" }
        }
    }

    static func tint(for attachment: MessageAttachment) -> Color {
        switch attachment.kind {
        case .pdf: .red
        case .skill: .purple
        case .tool: .accentColor
        case .text: .secondary
        case .document:
            if attachment.mimeType.contains("spreadsheet") { .green }
            else if attachment.mimeType.contains("presentation") { .orange }
            else { .blue }
        case .image: .secondary
        }
    }

    static func detail(for attachment: MessageAttachment) -> String {
        if attachment.kind == .skill { return "Skill" }
        if attachment.kind == .tool { return "Tool" }
        var parts: [String] = []
        if let bytes = attachment.byteCount, bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if attachment.truncated { parts.append("truncated") }
        return parts.joined(separator: " · ")
    }
}

struct ComposerAttachmentChip: View {
    var attachment: MessageAttachment
    var onPreview: () -> Void
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                if let image = AttachmentImage.nsImage(from: attachment) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    DocumentChipLabel(attachment: attachment)
                }
            }
            .buttonStyle(.plain)
            .help("View \(attachment.name)")
            .accessibilityLabel("View \(attachment.name)")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.black.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .help("Remove \(attachment.name)")
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.top, 5)
        .padding(.trailing, 5)
    }
}

/// Icon + name + size, used in the composer strip and in user bubbles.
struct DocumentChipLabel: View {
    var attachment: MessageAttachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: AttachmentBadge.symbol(for: attachment))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AttachmentBadge.tint(for: attachment))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                let detail = AttachmentBadge.detail(for: attachment)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Placeholder chip while a file is still being read.
struct ImportingChip: View {
    var name: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).frame(width: 22)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 5)
        .padding(.trailing, 5)
        .accessibilityLabel("Reading \(name)")
    }
}

struct AttachmentPreviewOverlay: View {
    var attachment: MessageAttachment
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                if attachment.kind != .image {
                    HStack(spacing: 8) {
                        Image(systemName: AttachmentBadge.symbol(for: attachment))
                            .foregroundStyle(AttachmentBadge.tint(for: attachment))
                        Text(attachment.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        let detail = AttachmentBadge.detail(for: attachment)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 10)
                    .padding(.trailing, 32)
                }
                content
            }
            .padding(.top, attachment.kind == .image ? 36 : 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .cueGlass(cornerRadius: 18, interactive: true)
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Close preview")
                .padding(10)
            }
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
            .padding(28)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(attachment.name)
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.kind {
        case .image:
            if let image = AttachmentImage.nsImage(from: attachment) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 720, maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(attachment.name)
                    .foregroundStyle(.secondary)
                    .padding(40)
            }
        case .pdf:
            if let data = AttachmentImage.pdfData(from: attachment) {
                PDFPreview(data: data)
                    .frame(width: 720, height: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                textPreview
            }
        case .document, .text, .skill:
            textPreview
        case .tool:
            VStack(spacing: 10) {
                Image(systemName: AttachmentBadge.symbol(for: attachment))
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text(ComposerTool.named(attachment.name)?.label ?? attachment.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(ComposerTool.named(attachment.name)?.description ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }

    private var textPreview: some View {
        ScrollView {
            Text(attachment.text ?? "")
                .font(.system(size: 12, design: attachment.kind == .skill ? .default : .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(width: 720, height: 520)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Native PDF rendering for the preview overlay.
struct PDFPreview: NSViewRepresentable {
    var data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
