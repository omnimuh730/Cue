import Foundation

/// Per-project instructions and knowledge files, rendered ahead of every turn in that project.
/// Knowledge is stored as extracted text (`MessageAttachment` without payloads) so it can ride
/// on both backends without re-reading files.
nonisolated struct ProjectContext: Equatable, Sendable {
    static let maxInstructionCharacters = SystemInstruction.maxCharacters
    static let maxKnowledgeCharacters = 400_000

    var name: String
    var instructions: String
    var knowledge: [MessageAttachment]

    var isEmpty: Bool {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && knowledge.isEmpty
    }

    var knowledgeCharacters: Int {
        knowledge.reduce(0) { $0 + ($1.text?.count ?? 0) }
    }

    /// Text placed after the base system instruction (Responses) or at the top of the Codex prompt.
    func promptBlock() -> String? {
        guard !isEmpty else { return nil }
        var sections: [String] = ["You are working inside the project \"\(name)\"."]
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sections.append("Project instructions:\n\(trimmed)")
        }
        if !knowledge.isEmpty {
            let files = knowledge.map { file -> String in
                let body = file.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return "<file name=\"\(file.name.replacingOccurrences(of: "\"", with: "'"))\">\n\(body.isEmpty ? "(empty)" : body)\n</file>"
            }
            sections.append("Project knowledge (reference files the user added to this project; prefer them over guesses):\n\n" + files.joined(separator: "\n\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Strips payloads so a knowledge entry is text only; images have no text and are rejected.
    static func knowledgeEntry(from attachment: MessageAttachment) -> MessageAttachment? {
        guard attachment.kind != .image, attachment.kind != .skill, attachment.kind != .tool else { return nil }
        var entry = attachment
        entry.dataURL = ""
        return entry
    }
}
