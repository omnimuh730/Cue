import Foundation

/// Text extraction for Office Open XML packages. Each reader walks the package XML with
/// `XMLParser` and produces Markdown-ish plain text the model can read: tables for sheets,
/// `## Slide N` sections for decks, paragraphs and pipe tables for Word documents.
nonisolated enum OOXMLText {
    static let maxSheetRows = 500
    static let maxSheetColumns = 60

    // MARK: - Word

    static func docx(_ archive: OOXMLArchive) throws -> String {
        let xml = try archive.data(forEntry: "word/document.xml")
        let reader = WordReader()
        reader.parse(xml)
        return reader.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Excel

    static func xlsx(_ archive: OOXMLArchive) throws -> String {
        let shared = (try? archive.data(forEntry: "xl/sharedStrings.xml")).map { SharedStringsReader.read($0) } ?? []
        let relationships = (try? archive.data(forEntry: "xl/_rels/workbook.xml.rels")).map { RelationshipsReader.read($0) } ?? [:]
        let sheets = (try? archive.data(forEntry: "xl/workbook.xml")).map { WorkbookReader.read($0) } ?? []

        var targets: [(name: String, entry: String)] = []
        for sheet in sheets {
            guard let target = relationships[sheet.relationshipID] else { continue }
            let entry = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            targets.append((sheet.name, entry))
        }
        if targets.isEmpty {
            // No workbook metadata: fall back to the worksheet files in numeric order.
            let entries = archive.names(withPrefix: "xl/worksheets/").filter { $0.hasSuffix(".xml") }
            targets = entries.sorted(by: numericFileOrder).enumerated().map { ("Sheet \($0.offset + 1)", $0.element) }
        }

        var sections: [String] = []
        for target in targets {
            guard let xml = try? archive.data(forEntry: target.entry) else { continue }
            let rows = SheetReader.read(xml, sharedStrings: shared)
            let table = markdownTable(rows)
            sections.append("## \(target.name)\n\n\(table.isEmpty ? "(empty)" : table)")
        }
        guard !sections.isEmpty else { throw OOXMLArchiveError.entryMissing("worksheets") }
        return sections.joined(separator: "\n\n")
    }

    static func markdownTable(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        var lines: [String] = []
        let limitedRows = Array(rows.prefix(maxSheetRows))
        let width = min(maxSheetColumns, limitedRows.map(\.count).max() ?? 0)
        guard width > 0 else { return "" }
        for (index, row) in limitedRows.enumerated() {
            var cells = row.prefix(width).map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
            while cells.count < width { cells.append("") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 {
                lines.append("|" + String(repeating: " --- |", count: width))
            }
        }
        if rows.count > maxSheetRows {
            lines.append("\n_\(rows.count - maxSheetRows) more rows omitted._")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - PowerPoint

    static func pptx(_ archive: OOXMLArchive) throws -> String {
        let slides = archive.names(withPrefix: "ppt/slides/").filter { $0.hasSuffix(".xml") }.sorted(by: numericFileOrder)
        guard !slides.isEmpty else { throw OOXMLArchiveError.entryMissing("slides") }
        var sections: [String] = []
        for (index, slide) in slides.enumerated() {
            guard let xml = try? archive.data(forEntry: slide) else { continue }
            var body = DrawingTextReader.read(xml)
            let fileName = slide.split(separator: "/").last.map(String.init) ?? ""
            if let relsXML = try? archive.data(forEntry: "ppt/slides/_rels/\(fileName).rels") {
                let rels = RelationshipsReader.readTargets(relsXML)
                for (_, target) in rels where target.type.hasSuffix("/notesSlide") {
                    let entry = normalize(target.target, relativeTo: "ppt/slides/")
                    if let notesXML = try? archive.data(forEntry: entry) {
                        let notes = DrawingTextReader.read(notesXML)
                        if !notes.isEmpty { body += "\n\nNotes:\n\(notes)" }
                    }
                }
            }
            sections.append("## Slide \(index + 1)\n\n\(body.isEmpty ? "(no text)" : body)")
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    /// Orders `slide2.xml` before `slide10.xml`.
    static func numericFileOrder(_ lhs: String, _ rhs: String) -> Bool {
        func number(_ path: String) -> Int {
            let digits = path.split(separator: "/").last?.filter(\.isNumber) ?? ""
            return Int(digits) ?? 0
        }
        let (l, r) = (number(lhs), number(rhs))
        return l == r ? lhs < rhs : l < r
    }

    static func normalize(_ target: String, relativeTo directory: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = directory.split(separator: "/").map(String.init)
        for component in target.split(separator: "/") {
            if component == ".." { _ = parts.popLast() } else if component != "." { parts.append(String(component)) }
        }
        return parts.joined(separator: "/")
    }

    static func columnIndex(fromReference reference: String) -> Int {
        var value = 0
        for scalar in reference.unicodeScalars {
            guard scalar.properties.isAlphabetic, let ascii = scalar.value.asciiUppercase else { break }
            value = value * 26 + Int(ascii - 64)
        }
        return max(0, value - 1)
    }
}

private extension UInt32 {
    var asciiUppercase: UInt32? {
        if (65...90).contains(self) { return self }
        if (97...122).contains(self) { return self - 32 }
        return nil
    }
}

// MARK: - Readers

private final class RelationshipsReader: NSObject, XMLParserDelegate {
    struct Target { var target: String; var type: String }
    private var map: [String: Target] = [:]

    static func read(_ xml: Data) -> [String: String] {
        readTargets(xml).mapValues(\.target)
    }

    static func readTargets(_ xml: Data) -> [String: Target] {
        let reader = RelationshipsReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.map
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard localName(elementName) == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
        map[id] = Target(target: target, type: attributes["Type"] ?? "")
    }
}

private final class WorkbookReader: NSObject, XMLParserDelegate {
    struct Sheet { var name: String; var relationshipID: String }
    private var sheets: [Sheet] = []

    static func read(_ xml: Data) -> [Sheet] {
        let reader = WorkbookReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard localName(elementName) == "sheet" else { return }
        let id = attributes["r:id"] ?? attributes.first { $0.key.hasSuffix(":id") }?.value ?? ""
        sheets.append(Sheet(name: attributes["name"] ?? "Sheet", relationshipID: id))
    }
}

private final class SharedStringsReader: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false

    static func read(_ xml: Data) -> [String] {
        let reader = SharedStringsReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch localName(elementName) {
        case "si": inItem = true; current = ""
        case "t": inText = inItem
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "t": inText = false
        case "si": strings.append(current); inItem = false
        default: break
        }
    }
}

private final class SheetReader: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [[String]] = []
    private var row: [String] = []
    private var cellColumn = 0
    private var cellType = ""
    private var value = ""
    private var capturing = false

    init(sharedStrings: [String]) {
        shared = sharedStrings
    }

    static func read(_ xml: Data, sharedStrings: [String]) -> [[String]] {
        let reader = SheetReader(sharedStrings: sharedStrings)
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch localName(elementName) {
        case "row":
            row = []
        case "c":
            cellColumn = attributes["r"].map(OOXMLText.columnIndex(fromReference:)) ?? row.count
            cellType = attributes["t"] ?? ""
            value = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "v", "t":
            capturing = false
        case "c":
            let text: String
            switch cellType {
            case "s": text = Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
            case "b": text = value == "1" ? "TRUE" : "FALSE"
            default: text = value
            }
            guard cellColumn < OOXMLText.maxSheetColumns else { return }
            while row.count <= cellColumn { row.append("") }
            row[cellColumn] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "row":
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        default:
            break
        }
    }
}

/// DrawingML text (`a:p` / `a:r` / `a:t`) as used by slides and notes.
private final class DrawingTextReader: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var paragraph = ""
    private var inText = false

    static func read(_ xml: Data) -> String {
        let reader = DrawingTextReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.paragraphs.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch localName(elementName) {
        case "p": paragraph = ""
        case "t": inText = true
        case "br": paragraph += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { paragraph += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "t": inText = false
        case "p":
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { paragraphs.append(trimmed) }
        default: break
        }
    }
}

/// WordprocessingML: paragraphs, tabs, breaks, and tables rendered as pipe rows.
private final class WordReader: NSObject, XMLParserDelegate {
    private(set) var output = ""
    private var paragraph = ""
    private var inText = false
    private var tableDepth = 0
    private var cells: [String] = []
    private var cell = ""

    func parse(_ xml: Data) {
        let parser = XMLParser(data: xml)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch localName(elementName) {
        case "p": paragraph = ""
        case "t": inText = true
        case "tab": paragraph += "\t"
        case "br", "cr": paragraph += "\n"
        case "tbl": tableDepth += 1
        case "tr": cells = []
        case "tc": cell = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { paragraph += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "t":
            inText = false
        case "p":
            if tableDepth > 0 {
                cell += (cell.isEmpty ? "" : " ") + paragraph.trimmingCharacters(in: .whitespaces)
            } else {
                output += paragraph.trimmingCharacters(in: .whitespaces) + "\n"
            }
        case "tc":
            cells.append(cell.replacingOccurrences(of: "|", with: "\\|"))
        case "tr":
            output += "| " + cells.joined(separator: " | ") + " |\n"
        case "tbl":
            tableDepth = max(0, tableDepth - 1)
            output += "\n"
        default:
            break
        }
    }
}

private func localName(_ element: String) -> String {
    if let colon = element.lastIndex(of: ":") { return String(element[element.index(after: colon)...]) }
    return element
}
