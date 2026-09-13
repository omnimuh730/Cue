import Foundation

nonisolated enum SkillScope: String, Codable, Sendable {
    case global
    case project
}

/// One Markdown skill: a reusable prompt the user invokes with `/name` in the composer.
nonisolated struct SkillDefinition: Identifiable, Equatable, Sendable {
    var name: String
    var description: String
    var body: String
    var sourcePath: String
    var scope: SkillScope

    var id: String { sourcePath }
}

/// Loads skills from disk. A skill is `name.md` or `name/SKILL.md`, optionally starting with a
/// YAML-style front matter block carrying `name:` and `description:`. Later roots win on name
/// collisions, so project skills override global ones. Pure and testable; no watching here.
nonisolated enum SkillCatalog {
    static let maxFileBytes = 200 * 1024
    static let skillFileName = "SKILL.md"

    /// `~/.cue/skills`, created on demand by the library.
    static var globalRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".cue/skills")
    }

    /// Folders scanned for a project with a code folder, in override order (last wins).
    static func projectRoots(folder: String) -> [URL] {
        let base = URL(fileURLWithPath: folder)
        return [base.appending(path: ".claude/skills"), base.appending(path: ".cue/skills")]
    }

    static func load(globalRoot: URL = globalRoot, projectFolder: String? = nil, fileManager: FileManager = .default) -> [SkillDefinition] {
        var byName: [String: SkillDefinition] = [:]
        var order: [String] = []
        let roots: [(URL, SkillScope)] = [(globalRoot, .global)] + (projectFolder.map { projectRoots(folder: $0).map { ($0, SkillScope.project) } } ?? [])
        for (root, scope) in roots {
            for skill in scan(root: root, scope: scope, fileManager: fileManager) {
                if byName[skill.name] == nil { order.append(skill.name) }
                byName[skill.name] = skill
            }
        }
        return order.compactMap { byName[$0] }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func scan(root: URL, scope: SkillScope, fileManager: FileManager = .default) -> [SkillDefinition] {
        guard let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var skills: [SkillDefinition] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                let file = item.appending(path: skillFileName)
                if let skill = read(file, fallbackName: item.lastPathComponent, scope: scope, fileManager: fileManager) {
                    skills.append(skill)
                }
            } else if item.pathExtension.lowercased() == "md" {
                let fallback = item.deletingPathExtension().lastPathComponent
                if let skill = read(item, fallbackName: fallback, scope: scope, fileManager: fileManager) {
                    skills.append(skill)
                }
            }
        }
        return skills
    }

    static func read(_ url: URL, fallbackName: String, scope: SkillScope, fileManager: FileManager = .default) -> SkillDefinition? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size <= maxFileBytes,
              let data = fileManager.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return parse(text, fallbackName: fallbackName, sourcePath: url.path, scope: scope)
    }

    static func parse(_ text: String, fallbackName: String, sourcePath: String, scope: SkillScope) -> SkillDefinition? {
        let (frontMatter, body) = splitFrontMatter(text)
        let name = normalizeName(frontMatter["name"] ?? fallbackName)
        guard !name.isEmpty else { return nil }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }
        let description = frontMatter["description"] ?? firstLine(of: trimmedBody)
        return SkillDefinition(name: name, description: description, body: trimmedBody, sourcePath: sourcePath, scope: scope)
    }

    /// Lower-cased, spaces to dashes, so `/name` matching is unambiguous.
    static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    /// Splits a leading `---` block into `key: value` pairs; nested YAML is not supported.
    static func splitFrontMatter(_ text: String) -> ([String: String], String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ([:], text) }
        var fields: [String: String] = [:]
        var index = 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                let body = lines[(index + 1)...].joined(separator: "\n")
                return (fields, body)
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let first = value.first, let last = value.last, first == last, first == "\"" || first == "'" {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty { fields[key] = value }
            }
            index += 1
        }
        // Unterminated front matter: treat the whole file as body.
        return ([:], text)
    }

    private static func firstLine(of body: String) -> String {
        let line = body.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        return String(stripped.prefix(120))
    }
}

/// `/query` at the start of the draft opens the skill picker.
nonisolated enum SkillInvocation {
    /// The text after the leading slash while the user is still typing the skill name; nil once
    /// the token ends (whitespace) or the draft does not start with `/`.
    static func query(in draft: String) -> String? {
        guard draft.hasPrefix("/") else { return nil }
        let token = draft.dropFirst()
        guard !token.contains(where: \.isWhitespace) else { return nil }
        return String(token)
    }

    /// Case-insensitive subsequence match, scored so prefix matches sort first.
    static func filter(_ skills: [SkillDefinition], query: String) -> [SkillDefinition] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return skills }
        return skills.compactMap { skill -> (SkillDefinition, Int)? in
            let name = skill.name.lowercased()
            if name.hasPrefix(needle) { return (skill, 0) }
            if name.contains(needle) { return (skill, 1) }
            if isSubsequence(needle, of: name) { return (skill, 2) }
            if skill.description.lowercased().contains(needle) { return (skill, 3) }
            return nil
        }
        .sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 < $1.1 }
        .map(\.0)
    }

    static func attachment(for skill: SkillDefinition) -> MessageAttachment {
        MessageAttachment(
            kind: .skill,
            mimeType: "text/markdown",
            name: skill.name,
            text: skill.body,
            byteCount: skill.body.utf8.count
        )
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var cursor = haystack.startIndex
        for character in needle {
            guard let found = haystack[cursor...].firstIndex(of: character) else { return false }
            cursor = haystack.index(after: found)
        }
        return true
    }
}
