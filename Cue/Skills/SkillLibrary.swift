import Foundation

/// Session-level skill list. Reloads when the global folder changes on disk (vnode source) and
/// when the active project changes, since projects contribute their own skill folders.
@MainActor
@Observable
final class SkillLibrary {
    private(set) var skills: [SkillDefinition] = []
    private(set) var projectFolder: String?
    let globalRoot: URL

    /// Lives for the app's lifetime alongside `AppSession`; the source is cancelled with the process.
    private var watcher: DispatchSourceFileSystemObject?

    init(globalRoot: URL = SkillCatalog.globalRoot) {
        self.globalRoot = globalRoot
        ensureGlobalRoot()
        reload()
        watch()
    }

    func reload(projectFolder: String? = nil) {
        self.projectFolder = projectFolder
        reload()
    }

    func reload() {
        let root = globalRoot
        let folder = projectFolder
        Task.detached(priority: .utility) { [weak self] in
            let loaded = SkillCatalog.load(globalRoot: root, projectFolder: folder)
            await MainActor.run { self?.skills = loaded }
        }
    }

    private func ensureGlobalRoot() {
        try? FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)
    }

    private func watch() {
        watcher?.cancel()
        let descriptor = open(globalRoot.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
    }
}
