import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Project settings overlay: name, instructions, knowledge files, and the optional code folder.
/// Edits save on the fly; the sheet closes with Escape, the close button, or a click outside.
struct ProjectSettingsView: View {
    @Bindable var session: AppSession
    var project: Project
    var onClose: () -> Void

    @State private var name = ""
    @State private var instructions = ""
    @State private var confirmDelete = false

    private var chats: Int {
        session.conversations.filter { $0.projectID == project.identifier }.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        nameField
                        instructionsField
                        knowledgeField
                        folderField
                        dangerZone
                    }
                    .padding(20)
                }
            }
            .frame(width: 560, height: 620)
            .cueGlass(cornerRadius: 24, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            name = project.name
            instructions = project.instructions ?? ""
        }
        .onChange(of: project.identifier) { _, _ in
            name = project.name
            instructions = project.instructions ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WorkspaceAvatar(letter: ProjectPaths.avatarLetter(project.name), isProject: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(chats == 1 ? "1 chat" : "\(chats) chats")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var nameField: some View {
        CueGlassField(title: "Name") {
            TextField("Project name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { session.renameProject(project, to: name) }
                .onChange(of: name) { _, next in session.renameProject(project, to: next) }
        }
    }

    private var instructionsField: some View {
        CueGlassField(
            title: "Instructions",
            help: "Sent with every chat in this project, after your global system instruction. Describe the role, the audience, and the tone you want."
        ) {
            VStack(alignment: .trailing, spacing: 4) {
                TextEditor(text: $instructions)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 180)
                    .onChange(of: instructions) { _, next in session.setProjectInstructions(project, next) }
                Text("\(instructions.count) / \(ProjectContext.maxInstructionCharacters)")
                    .font(.system(size: 10))
                    .foregroundStyle(instructions.count > ProjectContext.maxInstructionCharacters ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
            }
        }
    }

    private var knowledgeField: some View {
        let knowledge = project.knowledge
        let used = knowledge.reduce(0) { $0 + ($1.text?.count ?? 0) }
        return CueGlassField(
            title: "Knowledge",
            help: "Reference documents the model reads on every turn in this project: specs, notes, transcripts, spreadsheets. PDFs are stored as extracted text. Drop files here or add them with the button."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.importingKnowledge, id: \.self) { name in
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                ForEach(knowledge) { file in
                    HStack(spacing: 10) {
                        Image(systemName: AttachmentBadge.symbol(for: file))
                            .foregroundStyle(AttachmentBadge.tint(for: file))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            let detail = AttachmentBadge.detail(for: file)
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button {
                            session.previewAttachment = file
                        } label: {
                            Image(systemName: "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Preview \(file.name)")
                        Button {
                            session.removeKnowledge(file.id, from: project)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(file.name)")
                    }
                    .padding(.vertical, 2)
                }
                if knowledge.isEmpty, session.importingKnowledge.isEmpty {
                    Text("No knowledge files yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        session.pickKnowledgeFiles(for: project)
                    } label: {
                        Label("Add files…", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(used.formatted()) / \(ProjectContext.maxKnowledgeCharacters.formatted()) characters")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadDroppedURLs(providers) { session.addKnowledge($0, to: project) }
                return true
            }
        }
    }

    private var folderField: some View {
        CueGlassField(
            title: "Code folder",
            help: "Optional. With a folder linked, chats in this project run the Codex CLI read-only inside it and answer from the code. Instructions and knowledge still apply."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let folder = project.codeFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(folder)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder)
                        Spacer()
                        Text(project.catalog == nil ? "Not indexed" : "Indexed")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 14) {
                        Button("Change…") { session.openProjectFolder(for: project) }
                        Button("Re-index") {
                            session.indexPrompt = project
                            onClose()
                        }
                        Button("Unlink") { session.unlinkProjectFolder(project) }
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("Chats use the OpenAI Responses API with this project's instructions and knowledge.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        session.openProjectFolder(for: project)
                    } label: {
                        Label("Link a code folder…", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerZone: some View {
        HStack {
            Spacer()
            if confirmDelete {
                Text("Chats are kept and move to Personal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Delete project") {
                    session.removeProject(project)
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                Button("Cancel") { confirmDelete = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
            } else {
                Button("Delete project…") { confirmDelete = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock(); urls.append(url); lock.unlock()
                } else if let url = item as? URL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// Small name prompt shown when creating a project from the sidebar.
struct NewProjectDialog: View {
    var onCreate: (String) -> Void
    var onCancel: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: CueTheme.Spacing.sm) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    Text("New project")
                        .font(.system(size: 17, weight: .semibold))
                }
                Text("A project groups chats and gives them shared instructions and knowledge files. You can link a code folder afterwards.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($focused)
                    .onSubmit { submit() }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .cueGlass(cornerRadius: 16, interactive: true)
                    Button("Create", action: submit)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 420)
            .cueGlass(cornerRadius: 24, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            // The composer holds first responder; hand focus over once the field is in the hierarchy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func submit() {
        onCreate(name)
    }
}
