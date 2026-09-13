import Foundation
import Testing
@testable import Cue

struct ProjectContextTests {
    private let context = ProjectContext(
        name: "Interview prep",
        instructions: "Answer as a senior iOS engineer.",
        knowledge: [
            MessageAttachment(kind: .text, mimeType: "text/markdown", name: "resume.md", text: "10 years Swift."),
            MessageAttachment(kind: .pdf, mimeType: "application/pdf", name: "jd.pdf", text: "Role: iOS lead")
        ]
    )

    @Test func promptBlockOrdersInstructionsThenKnowledge() throws {
        let block = try #require(context.promptBlock())
        #expect(block.hasPrefix("You are working inside the project \"Interview prep\"."))
        let instructions = try #require(block.range(of: "Project instructions:\nAnswer as a senior iOS engineer."))
        let knowledge = try #require(block.range(of: "<file name=\"resume.md\">\n10 years Swift.\n</file>"))
        #expect(instructions.lowerBound < knowledge.lowerBound)
        #expect(block.contains("<file name=\"jd.pdf\">\nRole: iOS lead\n</file>"))
        #expect(ProjectContext(name: "Empty", instructions: "  ", knowledge: []).promptBlock() == nil)
    }

    @Test func knowledgeEntriesDropPayloadsAndImages() {
        let pdf = MessageAttachment(kind: .pdf, mimeType: "application/pdf", name: "a.pdf", dataURL: "data:application/pdf;base64,AA==", text: "words", byteCount: 3)
        let entry = ProjectContext.knowledgeEntry(from: pdf)
        #expect(entry?.dataURL == "")
        #expect(entry?.text == "words")
        #expect(entry?.byteCount == 3)
        let image = MessageAttachment(kind: .image, mimeType: "image/jpeg", name: "i.jpg", dataURL: "data:image/jpeg;base64,AA==")
        #expect(ProjectContext.knowledgeEntry(from: image) == nil)
        let skill = MessageAttachment(kind: .skill, mimeType: "text/markdown", name: "s", text: "b")
        #expect(ProjectContext.knowledgeEntry(from: skill) == nil)
    }

    @Test func responseInstructionsAppendProjectAfterGlobal() {
        let text = SystemInstruction.buildResponseInstructions("Be brief.", webSearchEnabled: true, project: context)
        #expect(text.hasPrefix("Be brief.\n\n\(SystemInstruction.webSearchHint)\n\nYou are working inside the project"))
        #expect(text.contains("Role: iOS lead"))
        let plain = SystemInstruction.buildResponseInstructions(nil, webSearchEnabled: false, project: nil)
        #expect(plain == SystemInstruction.defaultText)
    }

    @Test func codexPromptPutsProjectBeforeCatalogAndFiles() {
        let message = ChatRequestMessage(role: .user, content: "Explain the router.", attachments: [
            MessageAttachment(kind: .text, mimeType: "text/plain", name: "notes.txt", text: "attached notes")
        ])
        let prompt = CodexPrompt.build(messages: [message], catalog: "src/\n  Router.swift", project: context)
        let project = prompt.range(of: "You are working inside the project")!
        let catalog = prompt.range(of: "Project map catalog")!
        let files = prompt.range(of: "<file name=\"notes.txt\">")!
        #expect(project.lowerBound < catalog.lowerBound)
        #expect(catalog.lowerBound < files.lowerBound)
        #expect(prompt.hasSuffix("User question:\nExplain the router."))
    }
}
