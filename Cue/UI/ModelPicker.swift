import SwiftUI

struct ModelPicker: View {
    var settings: PublicSettings
    var onChange: (ModelID, ReasoningEffort) -> Void

    var body: some View {
        Menu {
            ForEach(ModelCatalog.models) { model in
                Button(model.label) {
                    onChange(model.id, ModelCatalog.normalizeEffort(settings.reasoningEffort, for: model.id))
                }
            }
            Divider()
            ForEach(ModelCatalog.definition(for: settings.model).supportedEfforts, id: \.self) { effort in
                Button(ModelCatalog.definition(for: effort).label) {
                    onChange(settings.model, effort)
                }
            }
        } label: {
            Text("\(ModelCatalog.definition(for: settings.model).shortLabel) · \(ModelCatalog.definition(for: settings.reasoningEffort).shortLabel)")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .cueGlass(cornerRadius: 14, interactive: true)
        }
        .menuStyle(.borderlessButton)
    }
}
