import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var id: String { path }
    var sizeText: String { isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

@MainActor
final class FileBrowserModel: ObservableObject {
    @Published var path = "/sdcard"
    @Published var items: [FileEntry] = []
    @Published var selection: Set<String> = []
    @Published var message: String?
    @Published var busy = false
    @Published var editing: EditorDocument?

    struct EditorDocument: Identifiable { let id = UUID(); let remotePath: String; var text: String }

    private let serial: String
    private let adb = ADBClient(adbURL: AppADB.url)
    private let service: FileService
    private let maxEditableBytes: Int64 = 2_000_000

    init(serial: String) {
        self.serial = serial
        self.service = FileService(adb: ADBClient(adbURL: AppADB.url), serial: serial)
    }

    var selectedEntries: [FileEntry] { items.filter { selection.contains($0.id) } }

    func load(_ newPath: String? = nil) {
        if let newPath { path = newPath.isEmpty ? "/" : newPath }
        busy = true; message = nil
        let target = path
        Task {
            defer { busy = false }
            let dir = target.hasSuffix("/") ? target : target + "/"
            let command = "find \(RemoteShell.quote(dir)) -mindepth 1 -maxdepth 1 -exec stat -L -c '%F|%s|%Y|%n' {} + 2>&1"
            do {
                let out = try await adb.run(serial: serial, arguments: ["exec-out", "sh", "-c", command], timeout: .seconds(30)).stdout
                var entries: [FileEntry] = []; var errors: [String] = []
                for line in String(decoding: out, as: UTF8.self).split(separator: "\n") {
                    let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
                    if parts.count == 4, let size = Int64(parts[1]), let time = TimeInterval(parts[2]) {
                        let full = String(parts[3])
                        entries.append(FileEntry(path: full, name: (full as NSString).lastPathComponent, isDirectory: parts[0].contains("directory"), size: size, modified: Date(timeIntervalSince1970: time)))
                    } else { errors.append(String(line)) }
                }
                items = entries.sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
                selection = []
                if entries.isEmpty, let first = errors.first { message = first } else if entries.isEmpty { message = "Empty folder" }
            } catch { items = []; message = error.localizedDescription }
        }
    }

    func goUp() {
        let parent = (path as NSString).deletingLastPathComponent
        load(parent.isEmpty ? "/" : parent)
    }

    func open(_ entry: FileEntry) {
        if entry.isDirectory { load(entry.path) } else { read(entry) }
    }

    /// Pulls the file to a temp folder; small text files open in the editor, anything else opens with the default Mac app.
    func read(_ entry: FileEntry) {
        busy = true
        Task {
            defer { busy = false }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidMonitor-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let local = dir.appendingPathComponent(entry.name)
            do {
                try await service.pull(remote: entry.path, local: local)
                if entry.size <= maxEditableBytes, let data = try? Data(contentsOf: local), let text = String(data: data, encoding: .utf8) {
                    editing = EditorDocument(remotePath: entry.path, text: text)
                } else { NSWorkspace.shared.open(local) }
            } catch { message = "Read failed: \(error.localizedDescription)" }
        }
    }

    func save(_ document: EditorDocument) {
        busy = true
        Task {
            defer { busy = false }
            let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try document.text.write(to: local, atomically: true, encoding: .utf8)
                try await service.push(local: local, remote: document.remotePath)
                message = "Saved \((document.remotePath as NSString).lastPathComponent)"
                load()
            } catch { message = "Write failed: \(error.localizedDescription)" }
        }
    }

    func download(_ entries: [FileEntry]) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Download Here"
        guard !entries.isEmpty, panel.runModal() == .OK, let folder = panel.url else { return }
        busy = true
        Task {
            defer { busy = false }
            do { for e in entries { try await service.pull(remote: e.path, local: folder) }; message = "Downloaded \(entries.count) item(s) → \(folder.lastPathComponent)" }
            catch { message = "Download failed: \(error.localizedDescription)" }
        }
    }

    func upload() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        upload(urls: panel.urls)
    }

    func upload(urls: [URL]) {
        busy = true
        let base = path.hasSuffix("/") ? path : path + "/"
        Task {
            defer { busy = false }
            do { for url in urls { try await service.push(local: url, remote: base + url.lastPathComponent) }; load() }
            catch { message = "Upload failed: \(error.localizedDescription)" }
        }
    }

    func delete(_ entries: [FileEntry]) {
        let alert = NSAlert(); alert.messageText = "Delete \(entries.count) item(s)?"
        alert.informativeText = entries.prefix(5).map(\.path).joined(separator: "\n") + (entries.count > 5 ? "\n…" : "")
        alert.alertStyle = .warning; alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { do { for e in entries { try await service.remove(e.path) }; load() } catch { message = "Delete failed: \(error.localizedDescription)" } }
    }

    func prompt(_ title: String, initial: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24); alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    func newFolder() {
        guard let name = prompt("New folder name") else { return }
        let base = path.hasSuffix("/") ? path : path + "/"
        Task { do { try await service.createDirectory(base + name); load() } catch { message = error.localizedDescription } }
    }

    func rename(_ entry: FileEntry) {
        guard let name = prompt("Rename", initial: entry.name), name != entry.name else { return }
        let target = (entry.path as NSString).deletingLastPathComponent + "/" + name
        Task { do { try await service.move(from: entry.path, to: target); load() } catch { message = error.localizedDescription } }
    }
}

struct FilesPanel: View {
    @StateObject private var model: FileBrowserModel
    @State private var pathText = "/sdcard"

    init(serial: String) { _model = StateObject(wrappedValue: FileBrowserModel(serial: serial)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                toolButton("chevron.up", "Parent folder") { model.goUp() }
                TextField("Path", text: $pathText).textFieldStyle(.roundedBorder).onSubmit { model.load(pathText) }
                toolButton("arrow.clockwise", "Reload") { model.load() }
                toolButton("folder.badge.plus", "New folder") { model.newFolder() }
                toolButton("square.and.arrow.up", "Upload files") { model.upload() }
                toolButton("square.and.arrow.down", "Download selected") { model.download(model.selectedEntries) }
                    .disabled(model.selection.isEmpty)
                toolButton("trash", "Delete selected") { model.delete(model.selectedEntries) }
                    .disabled(model.selection.isEmpty)
            }
            .padding(8)
            HStack(spacing: 6) {
                ForEach([("Internal", "/sdcard"), ("Download", "/sdcard/Download"), ("DCIM", "/sdcard/DCIM"), ("App data", "/sdcard/Android/data"), ("Root", "/")], id: \.1) { name, target in
                    Button(name) { model.load(target) }.buttonStyle(.link).font(.caption)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
            Divider()
            Table(model.items, selection: $model.selection) {
                TableColumn("Name") { e in
                    Label(e.name, systemImage: e.isDirectory ? "folder.fill" : icon(for: e.name))
                        .foregroundStyle(e.isDirectory ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                }
                TableColumn("Size") { e in Text(e.sizeText).foregroundStyle(.secondary) }.width(70)
                TableColumn("Modified") { e in Text(e.modified.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(120)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let picked = model.items.filter { ids.contains($0.id) }
                if let one = picked.first, picked.count == 1 {
                    Button(one.isDirectory ? "Open" : "Open / Edit") { model.open(one) }
                    Button("Rename…") { model.rename(one) }
                }
                if !picked.isEmpty {
                    Button("Download…") { model.download(picked) }
                    Button("Delete…", role: .destructive) { model.delete(picked) }
                }
            } primaryAction: { ids in
                if let entry = model.items.first(where: { ids.contains($0.id) }) { model.open(entry) }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.upload(urls: [url]) } }
                    }
                }
                return true
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
        .onAppear { model.load() }
        .onChange(of: model.path) { _, new in pathText = new }
        .sheet(item: $model.editing) { doc in FileEditor(document: doc, save: model.save) }
    }

    private func toolButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.help(help)
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "mp4", "mkv", "mov", "3gp": return "film"
        case "mp3", "m4a", "wav", "ogg": return "music.note"
        case "apk": return "shippingbox"
        case "zip", "gz", "tar", "7z": return "doc.zipper"
        case "txt", "log", "json", "xml", "csv", "md": return "doc.text"
        default: return "doc"
        }
    }
}

private struct FileEditor: View {
    @State var document: FileBrowserModel.EditorDocument
    let save: (FileBrowserModel.EditorDocument) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.remotePath).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save to device") { save(document); dismiss() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
            }
            .padding(10)
            Divider()
            TextEditor(text: $document.text).font(.system(size: 12, design: .monospaced))
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
