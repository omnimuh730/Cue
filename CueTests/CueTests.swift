import AppKit
import Foundation
import Testing
@testable import Cue

struct CueTests {
    @Test func continuationUsesPreviousResponseID() {
        let turns = [
            ChatTurn(id: UUID(), role: .user, content: "Hi", createdAt: .now, status: .complete, attachments: []),
            ChatTurn(
                id: UUID(),
                role: .assistant,
                content: "Hello",
                createdAt: .now,
                status: .complete,
                attachments: [],
                responseID: "resp_1"
            ),
            ChatTurn(id: UUID(), role: .user, content: "Again", createdAt: .now, status: .complete, attachments: [])
        ]
        let continuation = ChatContinuationBuilder.build(from: turns)
        #expect(continuation.previousResponseID == "resp_1")
        #expect(continuation.inputMessages?.count == 1)
        #expect(continuation.inputMessages?.first?.content == "Again")
    }

    @Test func continuationFallsBackWithoutResponseID() {
        let turns = [
            ChatTurn(id: UUID(), role: .user, content: "Hi", createdAt: .now, status: .complete, attachments: []),
            ChatTurn(id: UUID(), role: .assistant, content: "Hello", createdAt: .now, status: .complete, attachments: [])
        ]
        let continuation = ChatContinuationBuilder.build(from: turns)
        #expect(continuation.previousResponseID == nil)
        #expect(continuation.messages.count == 2)
    }

    @Test func effortNormalizesMaxForMini() {
        #expect(ModelCatalog.normalizeEffort(.max, for: .mini) == .xhigh)
        #expect(ModelCatalog.normalizeEffort(.low, for: .sol) == .low)
    }

    @Test func catalogGroupsPreserveOrder() {
        let groups = ModelCatalog.groupedModels
        #expect(groups.map(\.group) == ["GPT-5.6", "GPT-5.4"])
        #expect(groups[0].models.map(\.id) == [.sol, .terra, .luna])
        #expect(groups[1].models.map(\.id) == [.mini])
    }

    @Test func hotkeyFormatUsesMacKeycaps() {
        #expect(HotkeyFormat.keycaps(for: "CommandOrControl+Shift+H") == ["⌘", "⇧", "H"])
        #expect(HotkeyFormat.keycaps(for: "CommandOrControl+Alt+Up") == ["⌘", "⌥", "↑"])
        #expect(HotkeyFormat.keycaps(for: "CommandOrControl+num4") == ["⌘", "4"])
        #expect(HotkeyFormat.displayLabel(for: "CommandOrControl+Alt+Backspace") == "⌘ ⌥ ⌫")
    }

    @Test func hotkeyFormatRecordsCommandShiftH() {
        let accelerator = HotkeyFormat.accelerator(keyCode: 0x04, flags: [.command, .shift], characters: "h")
        #expect(accelerator == "CommandOrControl+Shift+H")
        #expect(HotkeyFormat.isRegisterable(accelerator ?? ""))
        #expect(HotkeyFormat.accelerator(keyCode: 53, flags: [], characters: "\u{1b}") == nil)
        #expect(HotkeyFormat.accelerator(keyCode: 0x04, flags: [], characters: "h") == nil)
    }

    @Test func hotkeyConflictDetectsDuplicate() {
        var map = HotkeyCatalog.defaults
        map[.newChat] = map[.toggleShowHide]
        let conflict = HotkeyCatalog.conflict(for: .newChat, in: map)
        #expect(conflict?.id == .toggleShowHide)
        #expect(HotkeyCatalog.conflict(for: .cycleEffort, in: HotkeyCatalog.defaults) == nil)
    }

    @Test func pricingUsesMiniRates() {
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cachedInputTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0)
        let estimate = Pricing.estimateTurnCost(model: .mini, usage: usage, webSearchCalls: 1)
        #expect(estimate.costUsd == 0.75 + 4.5 + 0.01)
        #expect(Pricing.formatUsd(0) == "$0.00")
    }

    @Test func systemInstructionAppendsWebSearch() {
        let text = SystemInstruction.buildResponseInstructions("", webSearchEnabled: true)
        #expect(text.contains("web search"))
        #expect(SystemInstruction.normalize(String(repeating: "a", count: 9_000)).count == 8_000)
    }

    @Test func remoteCursorClampsAndIgnoresJumps() {
        let moved = RemoteCursorMath.applyScreenDelta(
            virtualX: 10,
            virtualY: 10,
            lastScreenX: 0,
            lastScreenY: 0,
            screenX: 5,
            screenY: 8,
            width: 100,
            height: 100
        )
        #expect(moved.virtualX == 15)
        #expect(moved.virtualY == 18)
        #expect(moved.moved)

        let jump = RemoteCursorMath.applyScreenDelta(
            virtualX: 10,
            virtualY: 10,
            lastScreenX: 0,
            lastScreenY: 0,
            screenX: 4000,
            screenY: 0,
            width: 100,
            height: 100
        )
        #expect(jump.moved == false)
        #expect(jump.virtualX == 10)
    }

    @Test func composerViewportHugsTextHeightUntilTen() {
        let line = CueTheme.composerLineHeight
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: 0) == CueTheme.composerMinHeight)
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: line) == line)
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: line * 3) == line * 3)
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: line * 2.4) == ceil(line * 2.4))
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: line * 10) == CueTheme.composerMaxHeight)
        #expect(ComposerFieldMetrics.viewportHeight(forUsedHeight: line * 15) == CueTheme.composerMaxHeight)
        #expect(ComposerFieldMetrics.showsScroller(forUsedHeight: line * 10) == false)
        #expect(ComposerFieldMetrics.showsScroller(forUsedHeight: line * 11))
    }

    @Test func windowBoundsRespectWorkArea() {
        let next = WindowBounds.clampMovedBounds(
            RectValue(x: 10, y: 10, width: 100, height: 100),
            workArea: RectValue(x: 0, y: 0, width: 200, height: 200),
            dx: 500,
            dy: 0
        )
        #expect(next.x == 100)
    }

    @Test func acceleratorMatchParsesCommandShiftH() {
        let pattern = AcceleratorMatch.parseElectronAccelerator("CommandOrControl+Shift+H")
        #expect(pattern?.code == "KeyH")
        #expect(pattern?.shift == true)
        #expect(pattern?.metaOrCtrl == true)
        let payload = KeyPayload(code: "KeyH", key: "h", altKey: false, ctrlKey: false, metaKey: true, shiftKey: true)
        let matches = pattern.map { value in AcceleratorMatch.payloadMatches(payload, pattern: value) } ?? false
        #expect(matches)
    }

    @Test func energyVadStartsOnSpeech() {
        var vad = EnergyVAD(sampleRate: 16_000, speechThreshold: 0.01, silenceThreshold: 0.005, minSpeechMs: 20, minSilenceMs: 20, maxSpeechMs: 2000)
        let speech = [Float](repeating: 0.2, count: 1600)
        let events = vad.push(speech, chunkStartAbsolute: 0)
        let started = events.contains { event in
            if case .speechStart = event { return true }
            return false
        }
        #expect(started)
    }

    @Test @MainActor func streamUsageEventDoesNotHitExclusivityTrap() {
        let client = ResponsesClient()
        let state = ResponseStreamState()
        var events: [ChatStreamEvent] = []
        client.handle(
            type: "response.created",
            payload: ["response": ["id": "resp_1"]],
            settings: .default,
            state: state,
            yield: { events.append($0) }
        )
        client.handle(
            type: "response.completed",
            payload: [
                "response": [
                    "id": "resp_1",
                    "usage": [
                        "input_tokens": 12,
                        "output_tokens": 8
                    ]
                ]
            ],
            settings: .default,
            state: state,
            yield: { events.append($0) }
        )
        #expect(state.responseID == "resp_1")
        #expect(state.emittedUsage)
        #expect(events.count == 1)
    }
}
