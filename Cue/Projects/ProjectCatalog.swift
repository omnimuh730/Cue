import Foundation

/// Builds a compact "map catalog" of a project folder — layout, key files, and a README excerpt —
/// that is prepended to the Codex prompt so the agent can locate files before searching.
/// Ported from Halo's project-catalog; runs off the main actor.
nonisolated enum ProjectCatalog {
    static let skippedDirectories: Set<String> = [
        ".cache", ".git", ".idea", ".next", ".turbo", ".venv", "__pycache__", "build", "coverage",
        "dist", "node_modules", "out", "Pods", "release", "target", "vendor", "venv", "DerivedData",
        ".build", ".swiftpm", "xcuserdata"
    ]

    static let skippedExtensions: Set<String> = [
        "bin", "dylib", "exe", "icns", "ico", "jpg", "jpeg", "lock", "map", "mp3", "png", "so",
        "wasm", "woff", "woff2", "a", "o", "zip", "dmg", "mlmodelc"
    ]

    static let keyFileNames: Set<String> = [
        "agents.md", "cargo.toml", "composer.json", "dockerfile", "gemfile", "go.mod", "makefile",
        "package.json", "pyproject.toml", "readme", "readme.md", "readme.txt", "tsconfig.json",
        "package.swift", "claude.md", "podfile"
    ]

    static let maxDepth = 3
    static let maxEntries = 140
    static let maxCatalogChars = 7000
    static let maxReadmeChars = 360

    static func build(root: String, fileManager: FileManager = .default) -> String {
        let name = URL(fileURLWithPath: root).lastPathComponent
        var lines = ["# \(name)", "path: \(root)", ""]
        let about = readAbout(root: root, fileManager: fileManager)
        if !about.isEmpty {
            lines.append("## About")
            lines.append(contentsOf: about)
            lines.append("")
        }

        lines.append("## Layout")
        var layout: [String] = []
        walk(root: root, current: root, depth: 0, lines: &layout, fileManager: fileManager)
        lines.append(contentsOf: layout.isEmpty ? ["- (empty or unreadable)"] : layout)

        let keyFiles = collectKeyFiles(root: root, fileManager: fileManager)
        if !keyFiles.isEmpty {
            lines.append("")
            lines.append("## Key files")
            lines.append(contentsOf: keyFiles)
        }

        var catalog = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if catalog.count > maxCatalogChars {
            catalog = String(catalog.prefix(maxCatalogChars - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return catalog
    }

    // MARK: - About

    private static func readAbout(root: String, fileManager: FileManager) -> [String] {
        var lines: [String] = []
        let packageJSON = root + "/package.json"
        if let data = fileManager.contents(atPath: packageJSON),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = (parsed["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                lines.append("name: \(name)")
            }
            if let description = (parsed["description"] as? String)?.trimmingCharacters(in: .whitespaces), !description.isEmpty {
                lines.append("description: \(description)")
            }
            if let scripts = parsed["scripts"] as? [String: Any], !scripts.isEmpty {
                lines.append("scripts: \(scripts.keys.sorted().prefix(8).joined(separator: ", "))")
            }
        }
        for candidate in ["README.md", "README.txt", "README"] {
            let path = root + "/" + candidate
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let excerpt = readExcerpt(path: path, maxChars: maxReadmeChars, fileManager: fileManager)
            if !excerpt.isEmpty { lines.append("readme: \(excerpt)") }
            break
        }
        return lines
    }

    private static func readExcerpt(path: String, maxChars: Int, fileManager: FileManager) -> String {
        guard let data = fileManager.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return "" }
        let joined = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("<") }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if joined.count > maxChars {
            return String(joined.prefix(maxChars - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return joined
    }

    // MARK: - Layout

    private struct Entry {
        var name: String
        var path: String
        var isDirectory: Bool
    }

    private static func entries(in directory: String, fileManager: FileManager) -> [Entry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return names.compactMap { name in
            let path = directory + "/" + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
            return Entry(name: name, path: path, isDirectory: isDirectory.boolValue)
        }
    }

    private static func isVisible(_ entry: Entry) -> Bool {
        if entry.name.hasPrefix("."), entry.name != ".github" { return false }
        if entry.isDirectory, skippedDirectories.contains(entry.name) { return false }
        return true
    }

    private static func walk(root: String, current: String, depth: Int, lines: inout [String], fileManager: FileManager) {
        guard lines.count < maxEntries, depth <= maxDepth else { return }
        let visible = entries(in: current, fileManager: fileManager)
            .filter(isVisible)
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        let indent = String(repeating: "  ", count: depth)
        for entry in visible {
            guard lines.count < maxEntries else { return }
            let relative = String(entry.path.dropFirst(root.count + 1))
            if entry.isDirectory {
                lines.append("\(indent)- \(relative)/ (\(countImmediate(entry.path, fileManager: fileManager)))")
                walk(root: root, current: entry.path, depth: depth + 1, lines: &lines, fileManager: fileManager)
                continue
            }
            if shouldSkipFile(entry.name) { continue }
            lines.append("\(indent)- \(relative)")
        }
    }

    private static func countImmediate(_ directory: String, fileManager: FileManager) -> String {
        let visible = entries(in: directory, fileManager: fileManager).filter(isVisible)
        let directories = visible.filter(\.isDirectory).count
        let files = visible.count - directories
        var parts: [String] = []
        if directories > 0 { parts.append("\(directories) dir\(directories == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s")") }
        return parts.isEmpty ? "empty" : parts.joined(separator: ", ")
    }

    private static func collectKeyFiles(root: String, fileManager: FileManager) -> [String] {
        var found: [String] = []
        var queue = [root]
        while !queue.isEmpty, found.count < 24 {
            let current = queue.removeFirst()
            for entry in entries(in: current, fileManager: fileManager) {
                if entry.isDirectory {
                    if !skippedDirectories.contains(entry.name), !entry.name.hasPrefix(".") { queue.append(entry.path) }
                    continue
                }
                if keyFileNames.contains(entry.name.lowercased()) {
                    found.append("- " + String(entry.path.dropFirst(root.count + 1)))
                }
            }
        }
        return found
    }

    static func shouldSkipFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && skippedExtensions.contains(ext)
    }
}
