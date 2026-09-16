import SwiftUI

/// What listen has heard, sitting above the composer while it is armed. Compact by default:
/// the last few lines, the newest strongest, with the live row still moving. One click answers
/// the latest sentence; a row click quotes that line into the draft; the chevron opens the
/// whole log.
struct TranscriptStrip: View {
    var log: TranscriptLog
    var listening: Bool
    var answerShortcut: String
    var onAnswer: () -> Void
    var onQuote: (CaptionLine) -> Void
    var onClear: () -> Void

    @State private var expanded = false

    private static let compactRows = 3

    private var rows: [CaptionLine] {
        expanded ? log.lines : Array(log.lines.suffix(Self.compactRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if log.isEmpty {
                Text(listening ? "Listening…" : "Nothing heard yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        lines
                            .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 220)
                    .onAppear {
                        if let last = log.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                    .onChange(of: log.lines.last?.id) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            } else {
                lines
                    .padding(.bottom, 8)
            }
        }
        .cueGlass(cornerRadius: 16, interactive: true)
        .animation(.easeInOut(duration: 0.15), value: expanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Heard")
                        .font(.system(size: 11, weight: .semibold))
                    if log.lines.count > Self.compactRows, !expanded {
                        Text("\(log.lines.count)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Show only the latest lines" : "Show everything heard")

            if listening {
                CueMarkSpin(pointSize: 11, spinning: true, style: .busy)
                    .accessibilityLabel("Listening")
            }
            Spacer(minLength: 8)

            Button(action: onAnswer) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Answer")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(log.isEmpty ? Color.secondary : Color.accentColor)
            .background(Color.accentColor.opacity(log.isEmpty ? 0 : 0.12), in: Capsule())
            .disabled(log.isEmpty)
            .help("Send the last sentence heard as a question (\(answerShortcut))")

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .disabled(log.isEmpty)
            .help("Clear the transcript")
            .accessibilityLabel("Clear transcript")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var lines: some View {
        let shown = rows
        let answered = Set(log.lines.prefix(log.answeredCount).map(\.id))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { item in
                let line = item.element
                let isLast = item.offset == shown.count - 1
                Button {
                    onQuote(line)
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.text)
                            .font(.system(size: 13))
                            .lineLimit(expanded ? nil : (isLast ? 3 : 1))
                            .truncationMode(.head)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(color(for: line, isLast: isLast, answered: answered.contains(line.id)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TranscriptRowButtonStyle())
                .id(line.id)
                .help("Add this line to the draft")
            }
        }
    }

    private func color(for line: CaptionLine, isLast: Bool, answered: Bool) -> HierarchicalShapeStyle {
        if answered { return .quaternary }
        if line.isLive || isLast { return .primary }
        return .secondary
    }
}

private struct TranscriptRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed || hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .padding(.horizontal, 4)
            .onHover { hovering = $0 }
    }
}
