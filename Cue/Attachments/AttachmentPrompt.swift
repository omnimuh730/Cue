import Foundation

/// Renders non-image attachments as text the model reads ahead of the user's message. Shared by
/// the Responses client (as an `input_text` part) and the Codex prompt builder, so both backends
/// see documents and skills the same way.
nonisolated enum AttachmentPrompt {
    /// Text for every attachment the backend cannot take natively. `includePDFText` is true for
    /// Codex, which has no file input; the Responses client sends the PDF itself instead.
    static func text(for attachments: [MessageAttachment], includePDFText: Bool) -> String? {
        var skills: [String] = []
        var files: [String] = []
        for attachment in attachments {
            switch attachment.kind {
            case .image:
                continue
            case .pdf:
                guard includePDFText else { continue }
                files.append(fileBlock(attachment, fallback: "(no text layer; the PDF appears to be scanned)"))
            case .document, .text:
                files.append(fileBlock(attachment, fallback: "(empty)"))
            case .skill:
                skills.append("<skill name=\"\(escape(attachment.name))\">\n\(attachment.text ?? "")\n</skill>")
            }
        }
        var sections: [String] = []
        if !skills.isEmpty {
            sections.append("Follow this skill for the request below.\n\n" + skills.joined(separator: "\n\n"))
        }
        if !files.isEmpty {
            sections.append("The user attached these files:\n\n" + files.joined(separator: "\n\n"))
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static func fileBlock(_ attachment: MessageAttachment, fallback: String) -> String {
        let body = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "<file name=\"\(escape(attachment.name))\">\n\(body.isEmpty ? fallback : body)\n</file>"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
    }
}
