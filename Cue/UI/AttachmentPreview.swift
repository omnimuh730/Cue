import AppKit
import SwiftUI

enum AttachmentImage {
    /// Base64 → NSImage is expensive and views ask for the same image on every render, so decode once per attachment id.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func nsImage(from attachment: MessageAttachment) -> NSImage? {
        let key = attachment.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let payload = attachment.dataURL.split(separator: ",").last,
              let data = Data(base64Encoded: String(payload)),
              let image = NSImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ComposerAttachmentChip: View {
    var attachment: MessageAttachment
    var onPreview: () -> Void
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                Group {
                    if let image = AttachmentImage.nsImage(from: attachment) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

struct AttachmentPreviewOverlay: View {
    var attachment: MessageAttachment
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
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
            }
            .padding(.top, 36)
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
}
