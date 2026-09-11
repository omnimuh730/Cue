import Foundation

nonisolated struct CodexTurnRequest: Sendable {
    var binary: CodexBinary
    var apiKey: String
    var model: ModelID
    var effort: ReasoningEffort
    var projectPath: String
    var threadID: String?
    var prompt: String
}

nonisolated enum CodexError: LocalizedError {
    case missingBinary
    case launch(String)
    case exited(Int32, String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "Codex CLI was not found. Install it (`npm i -g @openai/codex`) or set its path in Settings → Projects."
        case .launch(let message):
            return "Could not start Codex: \(message)"
        case .exited(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Codex exited with code \(code)." : detail
        }
    }
}

/// Runs one `codex exec --experimental-json` turn as a child process and streams its JSONL
/// events through the same `ChatStreamEvent` contract the Responses client uses.
/// The sandbox is read-only and approvals are disabled, so Codex only reads the project.
struct CodexClient {
    func stream(_ request: CodexTurnRequest, signal: CancellationToken) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await Self.run(request, signal: signal) { continuation.yield($0) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.error("Response stopped."))
                    continuation.finish()
                } catch let failure as CodexEventMapper.Failure {
                    continuation.yield(.error(failure.message))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func arguments(for request: CodexTurnRequest) -> [String] {
        var args = [
            "exec", "--experimental-json",
            "--model", request.model.rawValue,
            "--sandbox", "read-only",
            "--cd", request.projectPath,
            "--skip-git-repo-check",
            "--config", "model_reasoning_effort=\"\(CodexPrompt.reasoningEffort(request.effort))\"",
            "--config", "approval_policy=\"never\""
        ]
        if let threadID = request.threadID, !threadID.isEmpty {
            args += ["resume", threadID]
        }
        return args
    }

    private static func environment(for binary: CodexBinary) -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "SHELL"] {
            if let value = current[key] { env[key] = value }
        }
        let path = ([binary.pathDirectories, ["/usr/local/bin", "/opt/homebrew/bin"]].flatMap { $0 } + [env["PATH"] ?? "/usr/bin:/bin"])
        env["PATH"] = path.filter { !$0.isEmpty }.joined(separator: ":")
        env["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] = "cue_desktop"
        return env
    }

    private static func run(_ request: CodexTurnRequest, signal: CancellationToken, yield: @Sendable (ChatStreamEvent) -> Void) async throws {
        yield(.start)
        yield(.status("Reading project…"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.binary.executable)
        process.arguments = arguments(for: request)
        var env = environment(for: request.binary)
        env["CODEX_API_KEY"] = request.apiKey
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: request.projectPath)

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let stderrCollector = OutputCollector()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrCollector.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            throw CodexError.launch(error.localizedDescription)
        }

        // Write the prompt then close stdin so `codex exec -` sees EOF.
        if let data = request.prompt.data(using: .utf8) {
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdin.fileHandleForWriting.close()

        let mapper = CodexEventMapper(model: request.model, effort: request.effort, threadID: request.threadID)
        let watchdog = Task.detached {
            while !Task.isCancelled {
                if signal.isCancelled {
                    if process.isRunning { process.terminate() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        defer { watchdog.cancel() }

        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                if Task.isCancelled || signal.isCancelled { throw CancellationError() }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                for event in try mapper.consume(json) {
                    yield(event)
                }
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }

        process.waitUntilExit()
        stderr.fileHandleForReading.readabilityHandler = nil
        stderrCollector.append(stderr.fileHandleForReading.readDataToEndOfFile())
        if signal.isCancelled { throw CancellationError() }
        if process.terminationStatus != 0 {
            throw CodexError.exited(process.terminationStatus, stderrCollector.text)
        }
        if !mapper.hasAgentText, let problem = mapper.lastItemError {
            throw CodexEventMapper.Failure.codex(problem)
        }
        yield(mapper.done())
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
