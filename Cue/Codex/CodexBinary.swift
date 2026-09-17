import Foundation

nonisolated struct CodexBinary: Equatable, Sendable {
    var executable: String
    /// Extra directories to prepend to PATH (the npm package ships `rg` in a sibling `codex-path`).
    var pathDirectories: [String]
    var source: String
}

/// Finds a native `codex` CLI. Order: the path saved in Settings, an executable bundled with Cue,
/// the user's PATH and the usual install prefixes, global npm packages, then the Codex CLI that
/// ships inside Halo.app. JS shims are unwrapped to the vendored native binary next to them.
nonisolated enum CodexBinaryLocator {
    static let vendorTriple: String = {
        #if arch(arm64)
        "aarch64-apple-darwin"
        #else
        "x86_64-apple-darwin"
        #endif
    }()

    static let npmPlatformPackage: String = {
        #if arch(arm64)
        "codex-darwin-arm64"
        #else
        "codex-darwin-x64"
        #endif
    }()

    static func resolve(override: String?, fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexBinary? {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            if let found = unwrap(candidate: expand(override), source: "Settings", fileManager: fileManager) {
                return found
            }
        }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "codex")?.path,
           let found = unwrap(candidate: bundled, source: "Bundled", fileManager: fileManager) {
            return found
        }
        for directory in searchDirectories(environment: environment) {
            let candidate = directory + "/codex"
            if let found = unwrap(candidate: candidate, source: directory, fileManager: fileManager) {
                return found
            }
        }
        for root in nodeModuleRoots(fileManager: fileManager) {
            for candidate in vendorCandidates(nodeModules: root) {
                if let found = unwrap(candidate: candidate, source: root, fileManager: fileManager) {
                    return found
                }
            }
        }
        return nil
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func searchDirectories(environment: [String: String]) -> [String] {
        let home = NSHomeDirectory()
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.codex/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin"
        ]
        for versions in ["\(home)/.nvm/versions/node", "\(home)/.fnm/node-versions"] {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: versions) {
                directories += names.sorted(by: >).map { "\(versions)/\($0)/bin" } + names.sorted(by: >).map { "\(versions)/\($0)/installation/bin" }
            }
        }
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func nodeModuleRoots(fileManager: FileManager) -> [String] {
        let home = NSHomeDirectory()
        var roots = [
            "/opt/homebrew/lib/node_modules",
            "/usr/local/lib/node_modules",
            "\(home)/.npm-global/lib/node_modules",
            "\(home)/.volta/tools/shared",
            "/Applications/Halo.app/Contents/Resources/app.asar.unpacked/node_modules",
            "\(home)/Applications/Halo.app/Contents/Resources/app.asar.unpacked/node_modules"
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let names = try? fileManager.contentsOfDirectory(atPath: nvm) {
            roots += names.sorted(by: >).map { "\(nvm)/\($0)/lib/node_modules" }
        }
        return roots
    }

    /// Every place npm has put the native binary: the platform package hoisted next to
    /// `@openai/codex`, nested under it as an optional dependency (npm ≥ 0.150), or vendored
    /// inside the main package itself (older releases).
    private static func vendorCandidates(nodeModules root: String) -> [String] {
        [
            "\(root)/@openai/\(npmPlatformPackage)/vendor/\(vendorTriple)/bin/codex",
            "\(root)/@openai/codex/node_modules/@openai/\(npmPlatformPackage)/vendor/\(vendorTriple)/bin/codex",
            "\(root)/@openai/codex/vendor/\(vendorTriple)/bin/codex",
            "\(root)/@openai/codex/vendor/\(vendorTriple)/codex/codex"
        ]
    }

    /// Accepts a path that may be a symlink or the npm JS shim and returns the native binary.
    private static func unwrap(candidate: String, source: String, fileManager: FileManager) -> CodexBinary? {
        guard fileManager.isExecutableFile(atPath: candidate) else { return nil }
        let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        if isNativeBinary(resolved, fileManager: fileManager) {
            return CodexBinary(executable: resolved, pathDirectories: pathDirectories(for: resolved, fileManager: fileManager), source: source)
        }
        // npm shim: <pkg>/bin/codex.js → vendored binary in the same or the platform package.
        let package = URL(fileURLWithPath: resolved).deletingLastPathComponent().deletingLastPathComponent().path
        let nodeModules = URL(fileURLWithPath: package).deletingLastPathComponent().deletingLastPathComponent().path
        for vendored in vendorCandidates(nodeModules: nodeModules) where fileManager.isExecutableFile(atPath: vendored) {
            if isNativeBinary(vendored, fileManager: fileManager) {
                return CodexBinary(executable: vendored, pathDirectories: pathDirectories(for: vendored, fileManager: fileManager), source: source)
            }
        }
        return nil
    }

    private static func isNativeBinary(_ path: String, fileManager: FileManager) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        // Mach-O (thin, 64-bit, fat) magic numbers; anything else is a script shim.
        let magics: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA]]
        return magics.contains(Array(head))
    }

    private static func pathDirectories(for executable: String, fileManager: FileManager) -> [String] {
        let bin = URL(fileURLWithPath: executable).deletingLastPathComponent()
        var dirs = [bin.path]
        let sibling = bin.deletingLastPathComponent().appendingPathComponent("codex-path").path
        if fileManager.fileExists(atPath: sibling) { dirs.append(sibling) }
        return dirs
    }
}
