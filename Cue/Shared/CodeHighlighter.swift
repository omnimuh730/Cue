import Foundation

nonisolated enum HighlightToken: Hashable, Sendable {
    case keyword
    case string
    case comment
    case number
    case type
    /// Decorators, preprocessor lines, shell variables, JSON / YAML / CSS keys, HTML attributes.
    case attribute
    case tag
}

/// One colored run of a code block, in UTF-16 offsets so it maps straight onto `NSAttributedString`.
nonisolated struct HighlightSpan: Hashable, Sendable {
    var range: Range<Int>
    var token: HighlightToken
}

/// Tokenizes fenced code for coloring. One hand-written scanner covers every language: strings,
/// comments, and numbers are near-universal, and the rest is a per-language keyword set plus a
/// few family quirks (decorators, preprocessor, tags, keys). It never fails — an unfinished
/// string while streaming just runs to the end of the block — and unknown languages get only
/// strings and numbers, since guessing comment syntax colors prose by mistake.
nonisolated enum CodeHighlighter {
    /// Past this many UTF-16 units the block is left plain; nobody reads a 20k-character listing
    /// for its colors and the scan would run on every streaming flush.
    static let maxLength = 20_000

    static func spans(_ source: String, language: String) -> [HighlightSpan] {
        guard let profile = Profile.for(language: language) else { return [] }
        let units = Array(source.utf16)
        guard units.count <= maxLength else { return [] }
        var scanner = Scanner(units: units, profile: profile)
        return scanner.run()
    }

    // MARK: - Language profiles

    struct Profile: Sendable {
        var keywords: Set<String> = []
        var caseInsensitiveKeywords = false
        var lineComment: [String] = []
        var blockComment: (open: String, close: String)?
        var quotes: [Character] = ["\"", "'"]
        var tripleQuotes = false
        /// Backtick strings may span lines (JS templates, Go raw strings).
        var backtickStrings = false
        /// Capitalized identifiers are types.
        var capitalizedTypes = false
        /// `@name` is an attribute / decorator.
        var atAttributes = false
        /// `#name` at a line start is a preprocessor directive.
        var hashDirectives = false
        /// `$name` is a shell variable.
        var dollarVariables = false
        /// `"key":` and bare `key:` are keys (JSON, YAML).
        var keyColons = false
        /// `<tag>` markup with `attr=` inside.
        var markup = false
        /// `property:` before a value (CSS).
        var cssProperties = false

        static func `for`(language raw: String) -> Profile? {
            let language = raw.trimmingCharacters(in: .whitespaces).lowercased()
            switch language {
            case "swift":
                return cLike(Keywords.swift, atAttributes: true)
            case "kotlin", "kt", "kts":
                return cLike(Keywords.kotlin, atAttributes: true)
            case "java":
                return cLike(Keywords.java, atAttributes: true)
            case "scala":
                return cLike(Keywords.scala, atAttributes: true)
            case "js", "javascript", "jsx", "mjs", "cjs", "ts", "typescript", "tsx":
                var profile = cLike(Keywords.javascript, atAttributes: true)
                profile.backtickStrings = true
                return profile
            case "go", "golang":
                var profile = cLike(Keywords.go)
                profile.backtickStrings = true
                return profile
            case "rust", "rs":
                return cLike(Keywords.rust)
            case "c", "h", "cpp", "cc", "cxx", "hpp", "c++", "objc", "objective-c", "objectivec", "m", "mm":
                var profile = cLike(Keywords.c, atAttributes: language.hasPrefix("obj") || language == "m" || language == "mm")
                profile.hashDirectives = true
                return profile
            case "cs", "csharp", "c#":
                var profile = cLike(Keywords.csharp)
                profile.hashDirectives = true
                return profile
            case "dart":
                return cLike(Keywords.dart, atAttributes: true)
            case "php":
                var profile = cLike(Keywords.php)
                profile.lineComment = ["//", "#"]
                profile.dollarVariables = true
                return profile
            case "python", "py", "python3":
                var profile = Profile()
                profile.keywords = Keywords.python
                profile.lineComment = ["#"]
                profile.tripleQuotes = true
                profile.capitalizedTypes = true
                profile.atAttributes = true
                return profile
            case "ruby", "rb":
                var profile = Profile()
                profile.keywords = Keywords.ruby
                profile.lineComment = ["#"]
                profile.capitalizedTypes = true
                profile.atAttributes = true
                return profile
            case "sh", "bash", "zsh", "shell", "console", "fish":
                var profile = Profile()
                profile.keywords = Keywords.shell
                profile.lineComment = ["#"]
                profile.backtickStrings = true
                profile.dollarVariables = true
                return profile
            case "sql", "mysql", "postgres", "postgresql", "sqlite", "psql":
                var profile = Profile()
                profile.keywords = Keywords.sql
                profile.caseInsensitiveKeywords = true
                profile.lineComment = ["--"]
                profile.blockComment = ("/*", "*/")
                profile.quotes = ["'"]
                return profile
            case "json", "jsonc", "json5":
                var profile = Profile()
                profile.keywords = ["true", "false", "null"]
                profile.lineComment = ["//"]
                profile.blockComment = ("/*", "*/")
                profile.keyColons = true
                return profile
            case "yaml", "yml", "toml":
                var profile = Profile()
                profile.keywords = ["true", "false", "null", "yes", "no", "on", "off", "~"]
                profile.lineComment = ["#"]
                profile.keyColons = true
                return profile
            case "html", "htm", "xml", "svg", "xhtml", "vue", "svelte", "plist":
                var profile = Profile()
                profile.blockComment = ("<!--", "-->")
                profile.markup = true
                return profile
            case "css", "scss", "sass", "less":
                var profile = Profile()
                profile.blockComment = ("/*", "*/")
                if language != "css" { profile.lineComment = ["//"] }
                profile.cssProperties = true
                profile.keywords = ["important", "media", "import", "keyframes", "font-face", "supports"]
                return profile
            case "":
                return nil
            default:
                // Strings and numbers only; comment markers vary too much to guess.
                var profile = Profile()
                profile.quotes = ["\""]
                return profile
            }
        }

        private static func cLike(_ keywords: Set<String>, atAttributes: Bool = false) -> Profile {
            var profile = Profile()
            profile.keywords = keywords
            profile.lineComment = ["//"]
            profile.blockComment = ("/*", "*/")
            profile.capitalizedTypes = true
            profile.atAttributes = atAttributes
            return profile
        }
    }

    // MARK: - Scanner

    private struct Scanner {
        let units: [UInt16]
        let profile: Profile
        var index = 0
        var spans: [HighlightSpan] = []
        /// Inside `<tag …>` while scanning markup, so bare words are attributes.
        var inTag = false

        init(units: [UInt16], profile: Profile) {
            self.units = units
            self.profile = profile
        }

        mutating func run() -> [HighlightSpan] {
            while index < units.count {
                let unit = units[index]
                if isNewline(unit) || unit == 0x20 || unit == 0x09 {
                    index += 1
                    continue
                }
                if scanComment() { continue }
                if scanString() { continue }
                if profile.markup, scanMarkup() { continue }
                if scanNumber() { continue }
                if scanWord() { continue }
                index += 1
            }
            return spans
        }

        // MARK: Pieces

        private mutating func scanComment() -> Bool {
            for marker in profile.lineComment where matches(marker) {
                // In shell and YAML `#` only opens a comment at a token boundary ("a#b" is a word).
                if marker == "#", index > 0, isWord(units[index - 1]) { continue }
                let start = index
                while index < units.count, !isNewline(units[index]) { index += 1 }
                emit(start, .comment)
                return true
            }
            if let block = profile.blockComment, matches(block.open) {
                let start = index
                index += block.open.utf16.count
                while index < units.count, !matches(block.close) { index += 1 }
                if index < units.count { index += block.close.utf16.count }
                emit(start, .comment)
                return true
            }
            return false
        }

        private mutating func scanString() -> Bool {
            let unit = units[index]
            if profile.tripleQuotes, matches("\"\"\"") || matches("'''") {
                let quote = String(utf16CodeUnits: Array(units[index..<index + 3]), count: 3)
                let start = index
                index += 3
                while index < units.count, !matches(quote) { index += 1 }
                if index < units.count { index += 3 }
                emit(start, .string)
                return true
            }
            if profile.backtickStrings, unit == 0x60 {
                let start = index
                index += 1
                while index < units.count, units[index] != 0x60 { index += 1 }
                if index < units.count { index += 1 }
                emit(start, .string)
                return true
            }
            guard let scalar = UnicodeScalar(unit), profile.quotes.contains(Character(scalar)) else { return false }
            // An apostrophe inside a word ("don't" in a comment-less unknown block) is not a string.
            if unit == 0x27, index > 0, isWord(units[index - 1]) { return false }
            let start = index
            index += 1
            while index < units.count {
                let current = units[index]
                if current == 0x5C { // backslash
                    index += 2
                    continue
                }
                if current == unit {
                    index += 1
                    break
                }
                if isNewline(current) { break }
                index += 1
            }
            index = min(index, units.count)
            let token: HighlightToken
            if profile.keyColons, nextNonSpace(from: index) == 0x3A { // ':'
                token = .attribute
            } else {
                token = .string
            }
            emit(start, token)
            return true
        }

        private mutating func scanMarkup() -> Bool {
            let unit = units[index]
            if unit == 0x3C { // '<'
                let start = index
                index += 1
                if index < units.count, units[index] == 0x2F { index += 1 } // '</'
                let nameStart = index
                while index < units.count, isWord(units[index]) || units[index] == 0x2D || units[index] == 0x3A {
                    index += 1
                }
                if index > nameStart {
                    emit(start, .tag)
                    inTag = true
                } else {
                    index = start + 1
                }
                return true
            }
            if unit == 0x3E { // '>'
                if inTag {
                    emit(index, .tag, end: index + 1)
                    inTag = false
                }
                index += 1
                return true
            }
            if inTag, unit == 0x2F, index + 1 < units.count, units[index + 1] == 0x3E { // '/>'
                emit(index, .tag, end: index + 2)
                index += 2
                inTag = false
                return true
            }
            if inTag, isWordStart(unit) {
                let start = index
                while index < units.count, isWord(units[index]) || units[index] == 0x2D || units[index] == 0x3A {
                    index += 1
                }
                emit(start, .attribute)
                return true
            }
            return false
        }

        private mutating func scanNumber() -> Bool {
            let unit = units[index]
            guard isDigit(unit) else { return false }
            // "v2" or "utf16" are words, not numbers.
            if index > 0, isWord(units[index - 1]) { return false }
            let start = index
            while index < units.count, isWord(units[index]) || units[index] == 0x2E {
                // A trailing "." belongs to prose / a member access, not the number.
                if units[index] == 0x2E, index + 1 < units.count, !isDigit(units[index + 1]) { break }
                index += 1
            }
            emit(start, .number)
            return true
        }

        private mutating func scanWord() -> Bool {
            let unit = units[index]
            let start = index
            if profile.atAttributes, unit == 0x40, index + 1 < units.count, isWordStart(units[index + 1]) {
                index += 1
                consumeWord()
                emit(start, .attribute)
                return true
            }
            if profile.dollarVariables, unit == 0x24, index + 1 < units.count {
                let next = units[index + 1]
                if next == 0x7B { // ${…}
                    index += 2
                    while index < units.count, units[index] != 0x7D, !isNewline(units[index]) { index += 1 }
                    if index < units.count, units[index] == 0x7D { index += 1 }
                    emit(start, .attribute)
                    return true
                }
                if isWord(next) {
                    index += 1
                    consumeWord()
                    emit(start, .attribute)
                    return true
                }
            }
            if profile.hashDirectives, unit == 0x23, atLineStart(start), index + 1 < units.count, isWordStart(units[index + 1]) {
                index += 1
                consumeWord()
                emit(start, .attribute)
                return true
            }
            guard isWordStart(unit) else { return false }
            consumeWord()
            // CSS "property:" and YAML "key:" are keys; the value after the colon is left alone.
            if profile.cssProperties || (profile.keyColons && atLineStart(start)) {
                var probe = index
                while probe < units.count, units[probe] == 0x2D { // css: "font-size"
                    probe += 1
                    while probe < units.count, isWord(units[probe]) { probe += 1 }
                }
                if probe < units.count, units[probe] == 0x3A, !(probe + 1 < units.count && units[probe + 1] == 0x3A) {
                    index = probe
                    emit(start, .attribute)
                    return true
                }
            }
            let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
            let lookup = profile.caseInsensitiveKeywords ? word.lowercased() : word
            if profile.keywords.contains(lookup) {
                emit(start, .keyword)
            } else if profile.capitalizedTypes, looksLikeType(word) {
                emit(start, .type)
            }
            return true
        }

        // MARK: Helpers

        private mutating func consumeWord() {
            while index < units.count, isWord(units[index]) { index += 1 }
        }

        private mutating func emit(_ start: Int, _ token: HighlightToken, end: Int? = nil) {
            let stop = end ?? index
            guard stop > start else { return }
            spans.append(HighlightSpan(range: start..<stop, token: token))
        }

        private func matches(_ literal: String) -> Bool {
            let needle = Array(literal.utf16)
            guard index + needle.count <= units.count else { return false }
            for (offset, unit) in needle.enumerated() where units[index + offset] != unit { return false }
            return true
        }

        private func nextNonSpace(from position: Int) -> UInt16? {
            var probe = position
            while probe < units.count, units[probe] == 0x20 || units[probe] == 0x09 { probe += 1 }
            return probe < units.count ? units[probe] : nil
        }

        /// Only whitespace or a list dash precedes `position` on its line.
        private func atLineStart(_ position: Int) -> Bool {
            var probe = position - 1
            while probe >= 0, !isNewline(units[probe]) {
                let unit = units[probe]
                if unit != 0x20, unit != 0x09, unit != 0x2D { return false }
                probe -= 1
            }
            return true
        }

        private func looksLikeType(_ word: String) -> Bool {
            guard let first = word.first, first.isUppercase, word.count > 1 else { return false }
            // ALL_CAPS is a constant, not a type.
            return word.contains { $0.isLowercase }
        }

        private func isNewline(_ unit: UInt16) -> Bool { unit == 0x0A || unit == 0x0D }
        private func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }
        private func isWordStart(_ unit: UInt16) -> Bool {
            (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F || unit > 0x7F
        }
        private func isWord(_ unit: UInt16) -> Bool { isWordStart(unit) || isDigit(unit) }
    }

    // MARK: - Keywords

    enum Keywords {
        static let swift: Set<String> = [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
            "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
            "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
            "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
            "throw", "switch", "where", "while", "Any", "as", "await", "async", "false", "is", "nil", "self",
            "Self", "super", "throws", "true", "try", "some", "any", "actor", "nonisolated", "mutating",
            "override", "final", "lazy", "weak", "unowned", "convenience", "required", "indirect", "consuming",
            "borrowing", "macro", "package"
        ]
        static let kotlin: Set<String> = [
            "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is",
            "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "val",
            "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field", "file",
            "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam", "value",
            "where", "abstract", "actual", "annotation", "companion", "const", "crossinline", "data", "enum",
            "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit", "noinline", "open",
            "operator", "out", "override", "private", "protected", "public", "reified", "sealed", "suspend",
            "tailrec", "vararg"
        ]
        static let java: Set<String> = [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue",
            "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for", "goto", "if",
            "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "package", "private",
            "protected", "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized",
            "this", "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null",
            "var", "record", "sealed", "permits", "yield"
        ]
        static let scala: Set<String> = java.union([
            "def", "val", "object", "trait", "match", "with", "yield", "lazy", "implicit", "override", "sealed",
            "case", "type", "given", "using", "extension", "enum", "then"
        ])
        static let javascript: Set<String> = [
            "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else",
            "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "return",
            "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "let",
            "static", "await", "async", "of", "true", "false", "null", "undefined", "from", "as",
            "interface", "type", "enum", "implements", "declare", "namespace", "readonly", "keyof", "abstract",
            "private", "protected", "public", "satisfies", "never", "unknown", "any", "string", "number", "boolean"
        ]
        static let go: Set<String> = [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
            "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
            "switch", "type", "var", "true", "false", "nil", "iota", "string", "int", "int64", "int32", "uint",
            "byte", "rune", "bool", "float64", "float32", "error", "any", "make", "new", "len", "cap", "append"
        ]
        static let rust: Set<String> = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
            "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
            "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
            "u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "isize", "f32", "f64", "bool", "str",
            "char", "macro_rules"
        ]
        static let c: Set<String> = [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum",
            "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void",
            "volatile", "while", "bool", "true", "false", "nullptr", "NULL", "class", "namespace", "template",
            "typename", "public", "private", "protected", "virtual", "override", "new", "delete", "this", "using",
            "try", "catch", "throw", "constexpr", "noexcept", "friend", "operator", "explicit", "mutable",
            "static_cast", "dynamic_cast", "reinterpret_cast", "const_cast", "size_t", "uint8_t", "uint32_t",
            "int32_t", "uint64_t", "int64_t", "id", "nil", "YES", "NO", "self", "super", "instancetype",
            "interface", "implementation", "end", "property", "synthesize", "selector", "protocol", "import"
        ]
        static let csharp: Set<String> = [
            "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked", "class", "const",
            "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "explicit",
            "extern", "false", "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int",
            "interface", "internal", "is", "lock", "long", "namespace", "new", "null", "object", "operator", "out",
            "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed",
            "short", "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw", "true", "try",
            "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using", "var", "virtual", "void",
            "volatile", "while", "async", "await", "record", "init", "get", "set", "value", "where", "yield"
        ]
        static let dart: Set<String> = [
            "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external",
            "factory", "false", "final", "finally", "for", "get", "hide", "if", "implements", "import", "in",
            "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required",
            "rethrow", "return", "sealed", "set", "show", "static", "super", "switch", "sync", "this", "throw",
            "true", "try", "typedef", "var", "void", "while", "with", "yield", "int", "double", "num", "bool"
        ]
        static let php: Set<String> = [
            "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const",
            "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor",
            "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "final", "finally", "fn", "for",
            "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof",
            "insteadof", "interface", "isset", "list", "match", "namespace", "new", "or", "print", "private",
            "protected", "public", "readonly", "require", "require_once", "return", "static", "switch", "throw",
            "trait", "try", "unset", "use", "var", "while", "xor", "yield", "true", "false", "null", "self",
            "parent", "this"
        ]
        static let python: Set<String> = [
            "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match",
            "case", "self", "cls", "print", "len", "range", "int", "str", "float", "list", "dict", "set", "tuple",
            "bool", "type", "isinstance", "super", "__init__"
        ]
        static let ruby: Set<String> = [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
            "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
            "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield",
            "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer", "puts", "lambda",
            "proc", "private", "public", "protected", "include", "extend", "raise"
        ]
        static let shell: Set<String> = [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
            "function", "select", "time", "return", "exit", "export", "local", "readonly", "declare", "typeset",
            "unset", "shift", "source", "alias", "set", "trap", "eval", "exec", "echo", "printf", "read", "cd",
            "test", "true", "false", "break", "continue", "sudo", "brew", "npm", "npx", "git", "cargo", "swift",
            "xcodebuild", "python", "python3", "pip", "node", "docker", "make", "curl", "grep", "sed", "awk",
            "cat", "ls", "mkdir", "rm", "cp", "mv", "chmod", "ssh", "yarn", "pnpm", "go", "rustc", "kubectl"
        ]
        static let sql: Set<String> = [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table",
            "drop", "alter", "add", "column", "index", "view", "primary", "key", "foreign", "references", "not",
            "null", "default", "unique", "check", "constraint", "join", "inner", "left", "right", "full", "outer",
            "cross", "on", "using", "group", "by", "order", "having", "limit", "offset", "asc", "desc", "distinct",
            "as", "and", "or", "in", "is", "like", "between", "exists", "case", "when", "then", "else", "end",
            "union", "all", "with", "recursive", "returning", "begin", "commit", "rollback", "transaction",
            "int", "integer", "bigint", "smallint", "text", "varchar", "char", "boolean", "date", "timestamp",
            "float", "real", "numeric", "decimal", "serial", "uuid", "json", "jsonb", "true", "false", "count",
            "sum", "avg", "min", "max", "coalesce", "cast", "if", "over", "partition", "window", "explain"
        ]
    }
}
