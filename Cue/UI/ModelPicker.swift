import SwiftUI

struct ModelPicker: View {
    @Bindable var session: AppSession
    @State private var open = false

    private var settings: PublicSettings { session.settings }
    private var model: ModelDefinition { ModelCatalog.definition(for: settings.model) }
    private var effort: EffortDefinition {
        ModelCatalog.definition(for: ModelCatalog.normalizeEffort(settings.reasoningEffort, for: settings.model))
    }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.shortLabel)
                    .font(.system(size: 13, weight: .medium))
                Text(effort.shortLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .cueGlass(cornerRadius: 17, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Model and thinking: \(model.label), \(effort.label)")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ModelPickerPanel(session: session)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ModelPickerPanel: View {
    @Bindable var session: AppSession
    @State private var hoveredModel: ModelID?

    private var settings: PublicSettings { session.settings }
    private var selectedModel: ModelID { settings.model }
    private var selectedEffort: ReasoningEffort {
        ModelCatalog.normalizeEffort(settings.reasoningEffort, for: settings.model)
    }
    private var effortDefinition: EffortDefinition { ModelCatalog.definition(for: selectedEffort) }
    private var availableEfforts: [ReasoningEffort] {
        ModelCatalog.definition(for: selectedModel).supportedEfforts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Used for your next message")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(ModelCatalog.groupedModels, id: \.group) { group in
                    Text(group.group)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 9)
                        .padding(.top, 8)
                        .padding(.bottom, 3)

                    ForEach(group.models) { model in
                        modelRow(model)
                    }
                }
            }

            thinkingControl
        }
        .padding(12)
        .frame(width: 368)
    }

    private func choose(model: ModelID, effort: ReasoningEffort) {
        session.settingsStore.patch { settings in
            settings.model = model
            settings.reasoningEffort = ModelCatalog.normalizeEffort(effort, for: model)
        }
    }

    private func modelRow(_ model: ModelDefinition) -> some View {
        let selected = model.id == selectedModel
        let hovered = hoveredModel == model.id

        return Button {
            choose(model: model.id, effort: selectedEffort)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected || hovered ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModel = hovering ? model.id : (hoveredModel == model.id ? nil : hoveredModel)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var thinkingControl: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Thinking", systemImage: "gauge")
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                Text(effortDefinition.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 15)

            Text(effortDefinition.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 23)
                .padding(.top, 4)
                .padding(.bottom, 12)

            EffortSlider(
                efforts: availableEfforts,
                value: selectedEffort,
                onChange: { choose(model: selectedModel, effort: $0) }
            )

            HStack {
                Text(ModelCatalog.definition(for: availableEfforts.first ?? .none).label)
                Spacer()
                Text(ModelCatalog.definition(for: availableEfforts.last ?? .max).label)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)

            if selectedModel == .mini {
                Text("GPT-5.4 mini supports up to Extra High.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}

private struct EffortSlider: View {
    var efforts: [ReasoningEffort]
    var value: ReasoningEffort
    var onChange: (ReasoningEffort) -> Void

    private var index: Int {
        max(0, efforts.firstIndex(of: value) ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(efforts.count, 2)
            let progress = CGFloat(index) / CGFloat(count - 1)
            let thumb: CGFloat = 22
            let trackHeight: CGFloat = 7
            let inset = thumb / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(trackHeight, (geo.size.width - thumb) * progress + inset), height: trackHeight)

                HStack(spacing: 0) {
                    ForEach(Array(efforts.enumerated()), id: \.element) { offset, _ in
                        Circle()
                            .fill(offset <= index ? Color.white.opacity(0.55) : Color.primary.opacity(0.28))
                            .frame(width: 4, height: 4)
                        if offset < efforts.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, inset - 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .offset(x: (geo.size.width - thumb) * progress)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        snap(at: drag.location.x, width: geo.size.width)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Thinking effort")
            .accessibilityValue(ModelCatalog.definition(for: value).label)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    let next = min(index + 1, efforts.count - 1)
                    onChange(efforts[next])
                case .decrement:
                    let next = max(index - 1, 0)
                    onChange(efforts[next])
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 30)
    }

    private func snap(at x: CGFloat, width: CGFloat) {
        guard efforts.count > 1, width > 0 else { return }
        let clamped = min(max(x / width, 0), 1)
        let next = Int((clamped * CGFloat(efforts.count - 1)).rounded())
        let effort = efforts[min(max(next, 0), efforts.count - 1)]
        if effort != value { onChange(effort) }
    }
}
