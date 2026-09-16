import Foundation

nonisolated enum ProjectPathError: LocalizedError, Equatable {
    case empty
    case invalid
    case missing
    case notDirectory
    case sensitive
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .empty: "Choose a project folder."
        case .invalid: "Invalid project path."
        case .missing: "That folder could not be found."
        case .notDirectory: "Choose a folder, not a file."
        case .sensitive: "That location cannot be used as a project."
        case .notAllowed: "Open this folder from the workspace switcher before chatting about it."
        }
    }
}

/// Guards which folders may become a Codex working directory. Ported from Halo's project-paths.
nonisolated enum ProjectPaths {
    /// Rejects filesystem roots and OS directories. `/usr/local/...` checkouts are allowed; `/usr` itself is not.
    static func isSensitive(_ resolved: String) -> Bool {
        var normalized = resolved.replacingOccurrences(of: "\\", with: "/")
        while normalized.count > 1, normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.isEmpty { normalized = "/" }
        let lower = normalized.lowercased()

        if normalized == "/" { return true }
        let blocked = ["/etc", "/system", "/bin", "/sbin", "/dev", "/proc", "/private/etc", "/library", "/applications"]
        for prefix in blocked where lower == prefix || lower.hasPrefix(prefix + "/") {
            return true
        }
        if lower == "/usr" || lower == "/private" || lower == "/users" || lower == "/volumes" { return true }
        if lower == NSHomeDirectory().lowercased() { return true }
        return false
    }

    static func isWithin(root: String, candidate: String) -> Bool {
        let rootParts = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        let candidateParts = URL(fileURLWithPath: candidate).standardizedFileURL.pathComponents
        guard candidateParts.count >= rootParts.count else { return false }
        return Array(candidateParts.prefix(rootParts.count)) == rootParts
    }

    /// Resolves symlinks and verifies the path is an existing, non-sensitive directory.
    static func usableDirectory(_ input: String, fileManager: FileManager = .default) throws(ProjectPathError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard !trimmed.contains("\0") else { throw .invalid }
        let resolved = URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDirectory) else { throw .missing }
        guard isDirectory.boolValue else { throw .notDirectory }
        guard !isSensitive(resolved) else { throw .sensitive }
        return resolved
    }

    static func displayPath(_ folderPath: String) -> String {
        let parts = folderPath.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        if parts.count <= 2 { return folderPath }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    static func avatarLetter(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
    }
}

