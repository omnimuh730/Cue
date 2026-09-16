import Foundation

nonisolated enum ChatStreamEvent: Sendable {
    case start
    /// Progress text while an agent backend explores (Codex); cleared by the first delta.
    case status(String)
    case delta(String)
    case usage(TokenUsage, costUsd: Double, model: ModelID, effort: ReasoningEffort, webSearchCalls: Int, breakdown: CostBreakdown)
    case done(timing: ResponseTiming, responseID: String?, codexThreadID: String?)
    case error(String)
    /// A web source the answer cites; one event per distinct URL, in the order they appear.
    case citation(Citation)
}

struct ResponsesClient {
    func stream(
        apiKey: String,
        settings: PublicSettings,
        continuation: ChatContinuation,
        signal: CancellationToken
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuationStream in
            let task = Task {
                do {
                    try await run(
                        apiKey: apiKey,
                        settings: settings,
                        continuation: continuation,
                        signal: signal,
                        yield: { continuationStream.yield($0) }
                    )
                    continuationStream.finish()
                } catch is CancellationError {
                    continuationStream.yield(.error("Response stopped."))
                    continuationStream.finish()
                } catch {
                    continuationStream.yield(.error(clean(error.localizedDescription)))
                    continuationStream.finish()
                }
            }
            continuationStream.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        apiKey: String,
        settings: PublicSettings,
        continuation: ChatContinuation,
        signal: CancellationToken,
        yield: (ChatStreamEvent) -> Void
    ) async throws {
        yield(.start)
        let startedAt = Date()
        let state = ResponseStreamState()

        let canChain = continuation.previousResponseID != nil && !(continuation.inputMessages ?? []).isEmpty
        do {
            try await streamOnce(
                apiKey: apiKey,
                settings: settings,
                continuation: continuation,
                useChain: canChain,
                signal: signal,
                onEvent: { type, payload in
                    handle(type: type, payload: payload, settings: settings, state: state, yield: yield)
                }
            )
        } catch let error as ChatError {
            if canChain, isMissingPrevious(error) {
                try await streamOnce(
                    apiKey: apiKey,
                    settings: settings,
                    continuation: continuation,
                    useChain: false,
                    signal: signal,
                    onEvent: { type, payload in
                        handle(type: type, payload: payload, settings: settings, state: state, yield: yield)
                    }
                )
            } else {
                throw error
            }
        }

        let finishedAt = Date()
        yield(.done(
            timing: ResponseTiming(
                timeToFirstTokenMs: max(0, ((state.firstTokenAt ?? finishedAt).timeIntervalSince(startedAt)) * 1000),
                totalMs: max(0, finishedAt.timeIntervalSince(startedAt) * 1000)
            ),
            responseID: state.responseID,
            codexThreadID: nil
        ))
    }

    func handle(
        type: String,
        payload: [String: Any],
        settings: PublicSettings,
        state: ResponseStreamState,
        yield: (ChatStreamEvent) -> Void
    ) {
        switch type {
        case "response.created":
            if let response = payload["response"] as? [String: Any], let id = response["id"] as? String {
                state.responseID = id
            }
        case "response.output_text.delta":
            if state.firstTokenAt == nil { state.firstTokenAt = Date() }
            if let delta = payload["delta"] as? String { yield(.delta(delta)) }
        case "response.web_search_call.completed":
            state.webSearchCalls += 1
        case "response.output_text.annotation.added":
            if let citation = Self.citation(from: payload["annotation"]), state.noteCitation(citation) {
                yield(.citation(citation))
            }
        case "response.completed", "response.incomplete":
            if let response = payload["response"] as? [String: Any] {
                // Annotations also ride on the final output; anything the stream missed lands here.
                for citation in Self.citations(inOutput: response["output"]) where state.noteCitation(citation) {
                    yield(.citation(citation))
                }
                emitUsage(from: response, settings: settings, state: state, yield: yield)
            }
        case "response.failed":
            let message = ((payload["response"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
            yield(.error(message ?? "The response failed."))
        case "error":
            yield(.error((payload["message"] as? String) ?? "Something went wrong while contacting OpenAI."))
        default:
            if let response = payload["response"] as? [String: Any], response["usage"] != nil {
                emitUsage(from: response, settings: settings, state: state, yield: yield)
            }
        }
    }

    private func emitUsage(
        from json: [String: Any],
        settings: PublicSettings,
        state: ResponseStreamState,
        yield: (ChatStreamEvent) -> Void
    ) {
        guard !state.emittedUsage else { return }
        if let id = json["id"] as? String, !id.isEmpty { state.responseID = id }
        guard let usage = readUsage(json["usage"]) else { return }
        if usage.inputTokens == 0, usage.outputTokens == 0, state.webSearchCalls == 0 { return }
        state.emittedUsage = true
        let calls = max(state.webSearchCalls, countWebSearchCalls(json["output"]))
        let estimate = Pricing.estimateTurnCost(model: settings.model, usage: usage, webSearchCalls: calls)
        yield(.usage(
            usage,
            costUsd: estimate.costUsd,
            model: settings.model,
            effort: settings.reasoningEffort,
            webSearchCalls: calls,
            breakdown: estimate.breakdown
        ))
    }

    private func streamOnce(
        apiKey: String,
        settings: PublicSettings,
        continuation: ChatContinuation,
        useChain: Bool,
        signal: CancellationToken,
        onEvent: (String, [String: Any]) -> Void
    ) async throws {
        var body: [String: Any] = [
            "model": settings.model.rawValue,
            "instructions": SystemInstruction.buildResponseInstructions(settings.systemInstruction, webSearchEnabled: continuation.webSearch, project: continuation.project),
            "input": toResponseInput(useChain ? (continuation.inputMessages ?? continuation.messages) : continuation.messages),
            "reasoning": ["effort": settings.reasoningEffort.rawValue],
            "store": true,
            "stream": true
        ]
        if continuation.webSearch {
            body["tools"] = [["type": "web_search"]]
            body["tool_choice"] = "auto"
        }
        if useChain, let previous = continuation.previousResponseID {
            body["previous_response_id"] = previous
        }
        if let cacheKey = continuation.promptCacheKey, !cacheKey.isEmpty {
            body["prompt_cache_key"] = cacheKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        signal.onCancel { bytes.task.cancel() }
        if Task.isCancelled || signal.isCancelled {
            bytes.task.cancel()
            throw CancellationError()
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var message = "OpenAI request failed (\(http.statusCode))."
            var collected = ""
            for try await line in bytes.lines {
                collected += line
            }
            if let data = collected.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let text = error["message"] as? String {
                message = text
            }
            if http.statusCode == 400, isMissingPrevious(ChatError.transport(message)) {
                throw ChatError.transport(message)
            }
            throw ChatError.transport(message)
        }

        for try await line in bytes.lines {
            if Task.isCancelled || signal.isCancelled { throw CancellationError() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }
            onEvent(type, json)
        }
    }

    /// Images and PDFs go to the model natively; documents, text files, and skills are rendered as
    /// an `input_text` part ahead of the user's own words.
    func toResponseInput(_ messages: [ChatRequestMessage]) -> [[String: Any]] {
        messages.map { message in
            if message.role == .assistant || message.attachments.isEmpty {
                return ["role": message.role.rawValue, "content": message.content]
            }
            var content: [[String: Any]] = []
            if let context = AttachmentPrompt.text(for: message.attachments, includePDFText: false) {
                content.append(["type": "input_text", "text": context])
            }
            for attachment in message.attachments {
                switch attachment.kind {
                case .image:
                    content.append([
                        "type": "input_image",
                        "image_url": attachment.dataURL,
                        "detail": "auto"
                    ])
                case .pdf:
                    content.append([
                        "type": "input_file",
                        "filename": attachment.name,
                        "file_data": attachment.dataURL
                    ])
                case .document, .text, .skill, .tool:
                    continue
                }
            }
            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content.append(["type": "input_text", "text": message.content])
            }
            if content.isEmpty {
                content.append(["type": "input_text", "text": ""])
            }
            return ["role": message.role.rawValue, "content": content]
        }
    }

    private func readUsage(_ raw: Any?) -> TokenUsage? {
        guard let usage = raw as? [String: Any] else { return nil }
        let details = usage["input_tokens_details"] as? [String: Any]
        let outputDetails = usage["output_tokens_details"] as? [String: Any]
        return TokenUsage(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cachedInputTokens: details?["cached_tokens"] as? Int ?? 0,
            cacheWriteTokens: details?["cache_write_tokens"] as? Int ?? 0,
            reasoningTokens: outputDetails?["reasoning_tokens"] as? Int ?? 0
        )
    }

    /// A `url_citation` annotation payload, or nil for any other annotation type.
    static func citation(from raw: Any?) -> Citation? {
        guard let annotation = raw as? [String: Any],
              (annotation["type"] as? String) == "url_citation",
              let url = annotation["url"] as? String, !url.isEmpty
        else { return nil }
        return Citation(
            url: url,
            title: annotation["title"] as? String ?? "",
            startIndex: annotation["start_index"] as? Int,
            endIndex: annotation["end_index"] as? Int
        )
    }

    /// Every `url_citation` on a response's output items, in document order.
    static func citations(inOutput output: Any?) -> [Citation] {
        guard let items = output as? [[String: Any]] else { return [] }
        return items.flatMap { item -> [Citation] in
            guard let content = item["content"] as? [[String: Any]] else { return [] }
            return content.flatMap { part -> [Citation] in
                (part["annotations"] as? [Any] ?? []).compactMap { citation(from: $0) }
            }
        }
    }

    private func countWebSearchCalls(_ output: Any?) -> Int {
        guard let items = output as? [[String: Any]] else { return 0 }
        return items.filter { ($0["type"] as? String) == "web_search_call" }.count
    }

    private func isMissingPrevious(_ error: ChatError) -> Bool {
        guard case .transport(let message) = error else { return false }
        return message.localizedCaseInsensitiveContains("previous_response_not_found")
            || message.localizedCaseInsensitiveContains("Previous response with id")
    }

    private func clean(_ message: String) -> String {
        var text = message
        if let range = text.range(of: #"^\d{3}\s+"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        if let brace = text.firstIndex(of: "{") {
            text = String(text[..<brace])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ResponseStreamState {
    var firstTokenAt: Date?
    var webSearchCalls = 0
    var responseID: String?
    var emittedUsage = false
    private var citedURLs: Set<String> = []

    /// True the first time a URL is seen, so each source is reported once.
    func noteCitation(_ citation: Citation) -> Bool {
        citedURLs.insert(citation.url).inserted
    }
}

final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Runs `handler` immediately if already cancelled, otherwise on the next `cancel()`.
    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }
        handlers.append(handler)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let handlers = self.handlers
        self.handlers = []
        lock.unlock()
        for handler in handlers { handler() }
    }
}
