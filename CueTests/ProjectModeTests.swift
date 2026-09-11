import Foundation
import Testing
@testable import Cue

struct ProjectModeTests {
    @Test func codexMapperStreamsDeltasFromAgentMessages() throws {
        let mapper = CodexEventMapper(model: .sol, effort: .low)
        var events: [ChatStreamEvent] = []
        events += try mapper.consume(["type": "thread.started", "thread_id": "thr_1"])
        events += try mapper.consume(["type": "item.started", "item": ["type": "agent_message", "text": ""]])
        events += try mapper.consume(["type": "item.updated", "item": ["type": "agent_message", "text": "Hel"]])
        events += try mapper.consume(["type": "item.completed", "item": ["type": "agent_message", "text": "Hello"]])

        #expect(mapper.threadID == "thr_1")
        var text = ""
        var statuses: [String] = []
        for event in events {
            if case .delta(let delta) = event { text += delta }
            if case .status(let status) = event { statuses.append(status) }
        }
        #expect(text == "Hello")
        #expect(statuses == ["Reading project…"])

        if case .done(_, let responseID, let threadID) = mapper.done() {
            #expect(responseID == nil)
            #expect(threadID == "thr_1")
        } else {
            Issue.record("expected done")
        }
    }

    @Test func codexMapperEmitsStatusOnlyBeforeFirstText() throws {
        let mapper = CodexEventMapper(model: .sol, effort: .low)
        let searching = try mapper.consume(["type": "item.started", "item": ["type": "command_execution", "command": "rg -n foo src"]])
        #expect(searching.count == 1)
        if case .status(let status) = searching[0] {
            #expect(status == "Searching rg -n foo src")
        } else {
            Issue.record("expected status")
        }
        // Same status twice is deduplicated.
        #expect(try mapper.consume(["type": "item.updated", "item": ["type": "command_execution", "command": "rg -n foo src"]]).isEmpty)
        _ = try mapper.consume(["type": "item.updated", "item": ["type": "agent_message", "text": "Answer"]])
        #expect(try mapper.consume(["type": "item.started", "item": ["type": "reasoning", "text": "…"]]).isEmpty)
    }

    @Test func codexMapperReportsUsageOnceAndFailures() throws {
        let mapper = CodexEventMapper(model: .mini, effort: .medium)
        let usage: [String: Any] = [
            "type": "turn.completed",
            "usage": ["input_tokens": 120, "output_tokens": 40, "cached_input_tokens": 20, "cache_write_input_tokens": 0, "reasoning_output_tokens": 8]
        ]
        let first = try mapper.consume(usage)
        #expect(first.count == 1)
        if case .usage(let tokens, _, let model, let effort, let calls, _) = first[0] {
            #expect(tokens.inputTokens == 120)
            #expect(tokens.reasoningTokens == 8)
            #expect(model == .mini)
            #expect(effort == .medium)
            #expect(calls == 0)
        } else {
            Issue.record("expected usage")
        }
        #expect(try mapper.consume(usage).isEmpty)

        #expect(throws: CodexEventMapper.Failure.codex("boom")) {
            try mapper.consume(["type": "turn.failed", "error": ["message": "boom"]])
        }
        #expect(throws: CodexEventMapper.Failure.codex("Codex failed.")) {
            try mapper.consume(["type": "error", "message": ""])
        }
    }

    @Test func codexMapperTreatsRetriesAndErrorItemsAsNonFatal() throws {
        let mapper = CodexEventMapper(model: .sol, effort: .low)
        let retry = try mapper.consume(["type": "error", "message": "Reconnecting... 2/5 (unexpected status 401)"])
        #expect(retry.count == 1)
        if case .status(let status) = retry[0] { #expect(status == "Reconnecting…") } else { Issue.record("expected status") }
        #expect(try mapper.consume(["type": "error", "message": "Reconnecting... 3/5"]).isEmpty)

        let fallback = try mapper.consume([
            "type": "item.completed",
            "item": ["type": "error", "message": "Falling back from WebSockets to HTTPS transport. unexpected status 401"]
        ])
        #expect(fallback.count == 1)
        #expect(mapper.lastItemError?.hasPrefix("Falling back") == true)
        #expect(!mapper.hasAgentText)

        _ = try mapper.consume(["type": "item.completed", "item": ["type": "agent_message", "text": "ok"]])
        #expect(mapper.hasAgentText)
    }

    @Test func codexStatusLabelsCommands() {
        #expect(CodexEventMapper.status(for: ["type": "command_execution", "command": "ls -la"]) == "Listing ls -la")
        #expect(CodexEventMapper.status(for: ["type": "command_execution", "command": "cat README.md"]) == "Reading files…")
        #expect(CodexEventMapper.status(for: ["type": "command_execution", "command": "git log"]) == "Git git log")
        #expect(CodexEventMapper.status(for: ["type": "command_execution", "command": ""]) == "Reading files…")
        #expect(CodexEventMapper.status(for: ["type": "web_search", "query": "swift 6"]) == "Searching swift 6")
        #expect(CodexEventMapper.status(for: ["type": "mcp_tool_call", "tool": "fetch"]) == "Using fetch")
        #expect(CodexEventMapper.status(for: ["type": "todo_list"]) == "Planning…")
        #expect(CodexEventMapper.status(for: ["type": "agent_message"]) == nil)
        let long = "python3 " + String(repeating: "x", count: 100)
        let status = CodexEventMapper.status(for: ["type": "command_execution", "command": long]) ?? ""
        #expect(status.hasSuffix("…"))
        #expect(status.count <= "Running ".count + 64)
    }

    @Test func codexPromptUsesLatestUserMessageAndCatalog() {
        let messages = [
            ChatRequestMessage(role: .user, content: "first", attachments: []),
            ChatRequestMessage(role: .assistant, content: "reply", attachments: []),
            ChatRequestMessage(role: .user, content: "  where is main?  ", attachments: [])
        ]
        #expect(CodexPrompt.build(messages: messages, catalog: nil) == "where is main?")
        #expect(CodexPrompt.build(messages: messages, catalog: "   ") == "where is main?")
        let withCatalog = CodexPrompt.build(messages: messages, catalog: "# repo\n- src/")
        #expect(withCatalog.hasPrefix("Project map catalog"))
        #expect(withCatalog.hasSuffix("User question:\nwhere is main?"))
        #expect(CodexPrompt.build(messages: [], catalog: nil) == "Please continue from the current project context.")
    }

    @Test func codexReasoningEffortMapsToCLIValues() {
        #expect(CodexPrompt.reasoningEffort(.none) == "minimal")
        #expect(CodexPrompt.reasoningEffort(.max) == "xhigh")
        #expect(CodexPrompt.reasoningEffort(.medium) == "medium")
    }

    @Test func sensitivePathsAreRejected() {
        #expect(ProjectPaths.isSensitive("/"))
        #expect(ProjectPaths.isSensitive("/usr"))
        #expect(ProjectPaths.isSensitive("/usr/"))
        #expect(ProjectPaths.isSensitive("/etc/ssh"))
        #expect(ProjectPaths.isSensitive("/System/Library"))
        #expect(ProjectPaths.isSensitive("/Users"))
        #expect(ProjectPaths.isSensitive(NSHomeDirectory()))
        #expect(!ProjectPaths.isSensitive("/usr/local/src/project"))
        #expect(!ProjectPaths.isSensitive("/Users/someone/Desktop/project"))
        #expect(!ProjectPaths.isSensitive("/private/tmp/work"))
    }

    @Test func usableDirectoryValidates() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("cue-project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("file.txt")
        try Data().write(to: file)

        let resolved = try ProjectPaths.usableDirectory(temp.path + "/")
        #expect(resolved.hasSuffix(temp.lastPathComponent))
        #expect(throws: ProjectPathError.empty) { try ProjectPaths.usableDirectory("   ") }
        #expect(throws: ProjectPathError.missing) { try ProjectPaths.usableDirectory(temp.path + "/nope") }
        #expect(throws: ProjectPathError.notDirectory) { try ProjectPaths.usableDirectory(file.path) }
        #expect(throws: ProjectPathError.sensitive) { try ProjectPaths.usableDirectory("/usr") }
        #expect(ProjectPaths.isWithin(root: temp.path, candidate: file.path))
        #expect(!ProjectPaths.isWithin(root: temp.path, candidate: temp.path + "-other/file"))
    }

    @Test func displayPathAndAvatar() {
        #expect(ProjectPaths.displayPath("/Users/me/Desktop/Utils/Cue") == "…/Utils/Cue")
        #expect(ProjectPaths.displayPath("/tmp") == "/tmp")
        #expect(ProjectPaths.avatarLetter("  cue") == "C")
        #expect(ProjectPaths.avatarLetter("") == "?")
    }

    @Test func projectCatalogSkipsNoiseAndListsKeyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cue-catalog-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src/app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("node_modules/dep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "# Title\nA tiny sample project.\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try #"{"name":"sample","description":"demo","scripts":{"build":"x","test":"y"}}"#.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "print(1)".write(to: root.appendingPathComponent("src/app/main.swift"), atomically: true, encoding: .utf8)
        try Data([0, 1]).write(to: root.appendingPathComponent("src/logo.png"))

        let catalog = ProjectCatalog.build(root: root.path)
        #expect(catalog.hasPrefix("# \(root.lastPathComponent)"))
        #expect(catalog.contains("name: sample"))
        #expect(catalog.contains("description: demo"))
        #expect(catalog.contains("scripts: build, test"))
        #expect(catalog.contains("readme: A tiny sample project."))
        #expect(catalog.contains("- src/ (1 dir, 1 file)"))
        #expect(catalog.contains("- src/app/main.swift"))
        #expect(!catalog.contains("node_modules"))
        #expect(!catalog.contains(".git"))
        #expect(!catalog.contains("logo.png"))
        #expect(catalog.contains("## Key files"))
        #expect(catalog.contains("- package.json"))
        #expect(catalog.contains("- README.md"))
    }

    @Test func codexBinaryLocatorUnwrapsShimNextToVendoredBinary() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cue-codex-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let shimDir = root.appendingPathComponent("node_modules/@openai/codex/bin")
        let vendorDir = root.appendingPathComponent("node_modules/@openai/\(CodexBinaryLocator.npmPlatformPackage)/vendor/\(CodexBinaryLocator.vendorTriple)/bin")
        try fm.createDirectory(at: shimDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: vendorDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: vendorDir.deletingLastPathComponent().appendingPathComponent("codex-path"), withIntermediateDirectories: true)
        let shim = shimDir.appendingPathComponent("codex.js")
        try "#!/usr/bin/env node\n".write(to: shim, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let binary = vendorDir.appendingPathComponent("codex")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0]).write(to: binary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let resolved = CodexBinaryLocator.resolve(override: shim.path, environment: ["PATH": ""])
        #expect(resolved?.executable.hasSuffix("/bin/codex") == true)
        #expect(resolved?.pathDirectories.contains { $0.hasSuffix("codex-path") } == true)
        #expect(resolved?.source == "Settings")

        let direct = CodexBinaryLocator.resolve(override: binary.path, environment: ["PATH": ""])
        #expect(direct?.executable == binary.resolvingSymlinksInPath().path)
    }
}
