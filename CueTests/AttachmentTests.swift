import AppKit
import Foundation
import CoreGraphics
import Testing
@testable import Cue

/// Builds tiny Office packages on the fly with the system `zip`, so the repo carries no binary fixtures.
enum OOXMLFixture {
    static func zip(_ files: [String: String], name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "cue-fixture-\(UUID().uuidString)")
        let source = root.appending(path: "src")
        for (path, contents) in files {
            let url = source.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let archive = root.appending(path: name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-q", "-r", archive.path] + files.keys.sorted()
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return archive
    }

    static let rels = #"<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>"#

    static func xlsx() throws -> URL {
        try zip([
            "[Content_Types].xml": "<Types/>",
            "xl/workbook.xml": #"<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Budget" sheetId="1" r:id="rId2"/><sheet name="Notes" sheetId="2" r:id="rId1"/></sheets></workbook>"#,
            "xl/_rels/workbook.xml.rels": #"<Relationships><Relationship Id="rId1" Target="worksheets/sheet2.xml"/><Relationship Id="rId2" Target="worksheets/sheet1.xml"/></Relationships>"#,
            "xl/sharedStrings.xml": #"<sst><si><t>Item</t></si><si><r><t>Total </t></r><r><t>cost</t></r></si><si><t>Coffee</t></si></sst>"#,
            "xl/worksheets/sheet1.xml": #"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>4.5</v></c><c r="C2" t="b"><v>1</v></c></row></sheetData></worksheet>"#,
            "xl/worksheets/sheet2.xml": #"<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>hello</t></is></c></row></sheetData></worksheet>"#
        ], name: "budget.xlsx")
    }

    static func pptx() throws -> URL {
        try zip([
            "[Content_Types].xml": "<Types/>",
            "ppt/slides/slide1.xml": #"<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="x"><p:txBody><a:p><a:r><a:t>Title </a:t></a:r><a:r><a:t>one</a:t></a:r></a:p><a:p><a:r><a:t>Bullet</a:t></a:r></a:p></p:txBody></p:sld>"#,
            "ppt/slides/slide2.xml": #"<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="x"><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:sld>"#,
            "ppt/slides/slide10.xml": #"<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="x"><a:p><a:r><a:t>Tenth</a:t></a:r></a:p></p:sld>"#,
            "ppt/slides/_rels/slide1.xml.rels": #"<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide1.xml"/></Relationships>"#,
            "ppt/notesSlides/notesSlide1.xml": #"<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="x"><a:p><a:r><a:t>Speaker note</a:t></a:r></a:p></p:notes>"#
        ], name: "deck.pptx")
    }

    static func docx() throws -> URL {
        try zip([
            "[Content_Types].xml": "<Types/>",
            "word/document.xml": #"<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:t>After</w:t></w:r></w:p></w:body></w:document>"#
        ], name: "letter.docx")
    }
}

struct AttachmentTests {
    @Test func zipReaderListsAndInflatesEntries() throws {
        let big = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 400)
        let url = try OOXMLFixture.zip(["a/b.txt": "hello", "big.txt": big], name: "t.zip")
        let archive = try OOXMLArchive(contentsOf: url)
        #expect(Set(archive.names).isSuperset(of: ["a/b.txt", "big.txt"]))
        #expect(try archive.string(forEntry: "a/b.txt") == "hello")
        #expect(try archive.string(forEntry: "big.txt") == big)
        #expect(archive.names(withPrefix: "a/") == ["a/b.txt"])
        #expect(throws: OOXMLArchiveError.entryMissing("nope")) { try archive.data(forEntry: "nope") }
    }

    @Test func zipReaderRejectsNonArchives() {
        #expect(throws: OOXMLArchiveError.notZip) { try OOXMLArchive(data: Data("not a zip at all, definitely not".utf8)) }
    }

    @Test func xlsxBecomesMarkdownTablesInWorkbookOrder() throws {
        let text = try OOXMLText.xlsx(try OOXMLArchive(contentsOf: try OOXMLFixture.xlsx()))
        let budget = try #require(text.range(of: "## Budget"))
        let notes = try #require(text.range(of: "## Notes"))
        #expect(budget.lowerBound < notes.lowerBound)
        #expect(text.contains("| Item | Total cost |"))
        #expect(text.contains("| --- | --- |"))
        #expect(text.contains("| Coffee | 4.5 | TRUE |"))
        #expect(text.contains("| hello |"))
    }

    @Test func pptxOrdersSlidesNumericallyAndIncludesNotes() throws {
        let text = try OOXMLText.pptx(try OOXMLArchive(contentsOf: try OOXMLFixture.pptx()))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "## Slide 1")
        #expect(text.contains("Title one\nBullet"))
        #expect(text.contains("Notes:\nSpeaker note"))
        let second = try #require(text.range(of: "Second"))
        let tenth = try #require(text.range(of: "Tenth"))
        #expect(second.lowerBound < tenth.lowerBound)
        #expect(text.contains("## Slide 3\n\nTenth"))
    }

    @Test func docxKeepsParagraphsAndTables() throws {
        let text = try OOXMLText.docx(try OOXMLArchive(contentsOf: try OOXMLFixture.docx()))
        #expect(text.hasPrefix("Hello world\n"))
        #expect(text.contains("| A | B |"))
        #expect(text.hasSuffix("After"))
    }

    @Test func importerClassifiesFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cue-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markdown = root.appending(path: "rules.mdc")
        try "# Rule\nBe kind.".write(to: markdown, atomically: true, encoding: .utf8)
        let md = try FileAttachmentImporter.load(markdown)
        #expect(md.kind == .text)
        #expect(md.text == "# Rule\nBe kind.")
        #expect(md.byteCount == 15)
        #expect(md.dataURL.isEmpty)

        let sheet = try FileAttachmentImporter.load(try OOXMLFixture.xlsx())
        #expect(sheet.kind == .document)
        #expect(sheet.mimeType.contains("spreadsheet"))
        #expect(sheet.text?.contains("Coffee") == true)

        let pdfURL = root.appending(path: "notes.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try #require(CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let pdf = try FileAttachmentImporter.load(pdfURL)
        #expect(pdf.kind == .pdf)
        #expect(pdf.dataURL.hasPrefix("data:application/pdf;base64,"))

        let binary = root.appending(path: "blob.xyz")
        try Data([0xff, 0xfe, 0x00, 0x01]).write(to: binary)
        #expect(throws: AttachmentImportError.unsupported("blob.xyz")) { try FileAttachmentImporter.load(binary) }
        let legacy = root.appending(path: "old.xls")
        try Data([0x00]).write(to: legacy)
        #expect(throws: AttachmentImportError.unsupported("old.xls")) { try FileAttachmentImporter.load(legacy) }
    }

    @Test func importerTruncatesLongText() {
        let (clipped, truncated) = FileAttachmentImporter.clip(String(repeating: "x", count: 50), limit: 10)
        #expect(truncated)
        #expect(clipped.hasPrefix("xxxxxxxxxx\n\n[truncated"))
        #expect(FileAttachmentImporter.clip("short", limit: 10) == ("short", false))
    }

    @Test func attachmentDecodesLegacyImageRows() throws {
        let legacy = #"{"id":"a","mimeType":"image/jpeg","name":"shot.jpg","dataURL":"data:image/jpeg;base64,AA=="}"#
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: Data(legacy.utf8))
        #expect(decoded.kind == .image)
        #expect(decoded.isImage)
        #expect(decoded.text == nil)
        #expect(!decoded.truncated)
        let roundTrip = try JSONDecoder().decode(MessageAttachment.self, from: try JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func promptRendersSkillsBeforeFiles() throws {
        let attachments = [
            MessageAttachment(kind: .text, mimeType: "text/plain", name: "a.md", text: "alpha"),
            MessageAttachment(kind: .skill, mimeType: "text/markdown", name: "review", text: "Be thorough."),
            MessageAttachment(kind: .pdf, mimeType: "application/pdf", name: "p.pdf", dataURL: "data:application/pdf;base64,AA==", text: "pdf words"),
            MessageAttachment(kind: .image, mimeType: "image/jpeg", name: "i.jpg", dataURL: "data:image/jpeg;base64,AA==")
        ]
        let responses = try #require(AttachmentPrompt.text(for: attachments, includePDFText: false))
        #expect(responses.hasPrefix("Follow this skill for the request below.\n\n<skill name=\"review\">\nBe thorough.\n</skill>"))
        #expect(responses.contains("<file name=\"a.md\">\nalpha\n</file>"))
        #expect(!responses.contains("pdf words"))
        let codex = try #require(AttachmentPrompt.text(for: attachments, includePDFText: true))
        #expect(codex.contains("<file name=\"p.pdf\">\npdf words\n</file>"))
        #expect(AttachmentPrompt.text(for: [attachments[3]], includePDFText: true) == nil)
    }

    @Test func responsesInputSendsPDFNativelyAndDocumentsAsText() throws {
        let message = ChatRequestMessage(role: .user, content: "Summarize", attachments: [
            MessageAttachment(kind: .pdf, mimeType: "application/pdf", name: "p.pdf", dataURL: "data:application/pdf;base64,AA==", text: "pdf words"),
            MessageAttachment(kind: .document, mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", name: "d.docx", text: "doc words"),
            MessageAttachment(kind: .image, mimeType: "image/jpeg", name: "i.jpg", dataURL: "data:image/jpeg;base64,AA==")
        ])
        let input = ResponsesClient().toResponseInput([message])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        let types = content.compactMap { $0["type"] as? String }
        #expect(types == ["input_text", "input_file", "input_image", "input_text"])
        #expect((content[0]["text"] as? String)?.contains("doc words") == true)
        #expect(content[1]["filename"] as? String == "p.pdf")
        #expect(content[1]["file_data"] as? String == "data:application/pdf;base64,AA==")
        #expect(content[3]["text"] as? String == "Summarize")
    }

    @Test func codexPromptInlinesAttachments() {
        let message = ChatRequestMessage(role: .user, content: "What is this?", attachments: [
            MessageAttachment(kind: .text, mimeType: "text/plain", name: "readme.md", text: "Cue is an overlay.")
        ])
        let prompt = CodexPrompt.build(messages: [message], catalog: "src/\n  main.swift")
        #expect(prompt.hasPrefix("Project map catalog"))
        #expect(prompt.contains("<file name=\"readme.md\">\nCue is an overlay.\n</file>"))
        #expect(prompt.hasSuffix("User question:\nWhat is this?"))
        let bare = CodexPrompt.build(messages: [ChatRequestMessage(role: .user, content: "", attachments: message.attachments)], catalog: nil)
        #expect(bare.hasSuffix("User question:\nPlease read the attached files."))
    }
}

/// Which representation a ⌘V in the composer picks up.
struct PasteboardIntentTests {
    @Test func filesWinOverEverything() {
        #expect(PasteboardIntent.classify(types: ["public.utf8-plain-text"], hasFiles: true, hasString: true) == .files)
    }

    @Test func imageWithACaptionStillPastesAsImage() {
        // A browser's "Copy Image": pixels first, then HTML and the alt text.
        let types = ["public.tiff", "public.png", "public.html", "public.utf8-plain-text"]
        #expect(PasteboardIntent.classify(types: types, hasFiles: false, hasString: true) == .image)
    }

    @Test func screenshotWithNoTextPastesAsImage() {
        #expect(PasteboardIntent.classify(types: ["public.png"], hasFiles: false, hasString: false) == .image)
    }

    @Test func spreadsheetCellsPasteAsText() {
        // Numbers and Excel lead with text and trail a rendered picture of the cells.
        let types = ["public.utf8-plain-text", "public.html", "public.tiff", "com.adobe.pdf"]
        #expect(PasteboardIntent.classify(types: types, hasFiles: false, hasString: true) == .text)
    }

    @Test func plainTextIsText() {
        #expect(PasteboardIntent.classify(types: ["public.utf8-plain-text"], hasFiles: false, hasString: true) == .text)
        #expect(PasteboardIntent.classify(types: [], hasFiles: false, hasString: false) == .text)
    }
}

/// Edit shortcuts the composer has to dispatch itself, since Cue is rarely the active app.
struct EditingShortcutTests {
    @Test func commandLettersMapToEditActions() {
        #expect(EditingShortcut.action(key: "v", command: true, shift: false, other: false) == #selector(NSText.paste(_:)))
        #expect(EditingShortcut.action(key: "v", command: true, shift: true, other: false) == #selector(NSTextView.pasteAsPlainText(_:)))
        #expect(EditingShortcut.action(key: "c", command: true, shift: false, other: false) == #selector(NSText.copy(_:)))
        #expect(EditingShortcut.action(key: "x", command: true, shift: false, other: false) == #selector(NSText.cut(_:)))
        #expect(EditingShortcut.action(key: "a", command: true, shift: false, other: false) == #selector(NSText.selectAll(_:)))
        #expect(EditingShortcut.action(key: "z", command: true, shift: false, other: false) == Selector(("undo:")))
        #expect(EditingShortcut.action(key: "z", command: true, shift: true, other: false) == Selector(("redo:")))
    }

    @Test func otherCombosAreLeftAlone() {
        // Plain typing, and combos with ⌥/⌃ (Cue's own global hotkeys live there).
        #expect(EditingShortcut.action(key: "v", command: false, shift: false, other: false) == nil)
        #expect(EditingShortcut.action(key: "v", command: true, shift: false, other: true) == nil)
        #expect(EditingShortcut.action(key: "n", command: true, shift: false, other: false) == nil)
    }
}
