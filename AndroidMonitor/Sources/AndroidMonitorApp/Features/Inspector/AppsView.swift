import AppKit
import SwiftUI

struct PhoneApp: Identifiable, Hashable {
    let id: String
    let label: String
    let version: String
    let isSystem: Bool
    let isDebuggable: Bool
    let icon: NSImage?
    static func == (a: PhoneApp, b: PhoneApp) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class AppsModel: ObservableObject {
    @Published var apps: [PhoneApp] = []
    @Published var loading = false
    @Published var message: String?
    private let serial: String
    private let adb = ADBClient(adbURL: AppADB.url)
    private var task: Task<Void, Never>?

    init(serial: String) { self.serial = serial }

    func load() {
        task?.cancel(); apps = []; loading = true; message = nil
        let serial = serial
        task = Task {
            defer { loading = false }
            guard let jar = Bundle.main.url(forResource: "amclip", withExtension: "jar"),
                  (try? await adb.run(serial: serial, arguments: ["push", jar.path, "/data/local/tmp/amclip.jar"], timeout: .seconds(20))) != nil else {
                message = "Could not start the app lister"; return
            }
            var buffer = ""
            do {
                let stream = adb.stream(serial: serial, arguments: ["exec-out", "CLASSPATH=/data/local/tmp/amclip.jar", "app_process", "/", "AppsHelper"])
                for try await chunk in stream {
                    buffer += String(decoding: chunk, as: UTF8.self)
                    var lines = buffer.components(separatedBy: "\n"); buffer = lines.removeLast()
                    let parsed = lines.compactMap(Self.parse)
                    if !parsed.isEmpty { apps = (apps + parsed).sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending } }
                }
            } catch { message = error.localizedDescription }
        }
    }

    private static func parse(_ line: String) -> PhoneApp? {
        let f = line.components(separatedBy: "\t")
        guard f.count >= 5 else { return nil }
        func text(_ s: String) -> String { Data(base64Encoded: s).map { String(decoding: $0, as: UTF8.self) } ?? s }
        return PhoneApp(id: f[0], label: text(f[1]), version: text(f[3]), isSystem: f[2].hasPrefix("S"), isDebuggable: f[2].contains("D"),
                        icon: Data(base64Encoded: f[4]).flatMap { NSImage(data: $0) })
    }

    func run(_ args: [String], done: String) {
        Task {
            do { _ = try await adb.run(serial: serial, arguments: args, timeout: .seconds(60)); message = done }
            catch { message = error.localizedDescription }
        }
    }

    func launch(_ app: PhoneApp) { run(["shell", "monkey", "-p", app.id, "-c", "android.intent.category.LAUNCHER", "1"], done: "Launched \(app.label)") }
    func stop(_ app: PhoneApp) { run(["shell", "am", "force-stop", app.id], done: "Stopped \(app.label)") }
    func info(_ app: PhoneApp) { run(["shell", "am", "start", "-a", "android.settings.APPLICATION_DETAILS_SETTINGS", "-d", "package:\(app.id)"], done: "Opened settings for \(app.label)") }

    func confirm(_ title: String, _ detail: String, action: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }

    func clearData(_ app: PhoneApp) { confirm("Clear data of \(app.label)?", "All app data and login state will be erased.") { self.run(["shell", "pm", "clear", app.id], done: "Cleared \(app.label)") } }
    func uninstall(_ app: PhoneApp) {
        confirm("Uninstall \(app.label)?", app.id) {
            self.run(["shell", "pm", "uninstall", app.id], done: "Uninstalled \(app.label)")
            self.apps.removeAll { $0.id == app.id }
        }
    }

    func install() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "apk") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = "Installing \(url.lastPathComponent)…"
        Task {
            do { _ = try await adb.run(serial: serial, arguments: ["install", "-r", url.path], timeout: .seconds(600)); message = "Installed"; load() }
            catch { message = error.localizedDescription }
        }
    }

    func pullAPK(_ app: PhoneApp) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Save APK Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            do {
                let out = try await adb.run(serial: serial, arguments: ["shell", "pm", "path", app.id], timeout: .seconds(15)).stdout
                guard let path = String(decoding: out, as: UTF8.self).split(separator: "\n").first?.replacingOccurrences(of: "package:", with: "") else { message = "No APK path"; return }
                _ = try await adb.run(serial: serial, arguments: ["pull", path.trimmingCharacters(in: .whitespaces), folder.appendingPathComponent("\(app.id).apk").path], timeout: .seconds(600))
                message = "Saved \(app.id).apk"
            } catch { message = error.localizedDescription }
        }
    }
}
