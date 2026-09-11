import AppKit
import SwiftUI

final class HotkeyRecordingController {
    private(set) var action: HotkeyAction?
    private var monitor: Any?

    func start(
        _ action: HotkeyAction,
        assign: @escaping (HotkeyAction, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        stop()
        self.action = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.isARepeat { return nil }
            if event.keyCode == 53 {
                self?.stop()
                DispatchQueue.main.async { cancel() }
                return nil
            }
            guard let accelerator = HotkeyFormat.accelerator(from: event),
                  HotkeyFormat.isRegisterable(accelerator)
            else { return nil }
            self?.stop()
            DispatchQueue.main.async { assign(action, accelerator) }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        action = nil
    }
}

struct HotkeyChip: View {
    var accelerator: String
    var isRecording: Bool
    var conflict: String?
    var onRecord: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: onRecord) {
                Group {
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text("Press keys…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(HotkeyFormat.keycaps(for: accelerator).enumerated()), id: \.offset) { _, cap in
                                Text(cap)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Color.primary.opacity(0.08))
                                    )
                            }
                        }
                    }
                }
                .frame(minWidth: 132, minHeight: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isRecording ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press a key combination, or Esc to cancel" : "Click to record a new shortcut")

            if let conflict, !isRecording {
                Text("Also used by \(conflict)")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}
