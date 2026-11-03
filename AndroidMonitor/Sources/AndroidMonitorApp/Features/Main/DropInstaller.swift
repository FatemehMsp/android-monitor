import SwiftUI
import UniformTypeIdentifiers

/// Handles files dropped on a device window: `.apk` files are installed, anything else is pushed to /sdcard/Download.
@MainActor
final class DropInstaller: ObservableObject {
    @Published var status: String?
    @Published var busy = false
    @Published var targeted = false

    private let serial: String
    private let adb = ADBClient(adbURL: AppADB.url)
    private var queue: [URL] = []
    private var clearTask: Task<Void, Never>?

    init(serial: String) { self.serial = serial }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.enqueue(url) }
            }
        }
        return true
    }

    private func enqueue(_ url: URL) {
        queue.append(url)
        if !busy { processNext() }
    }

    private func processNext() {
        guard !queue.isEmpty else { busy = false; scheduleClear(); return }
        busy = true
        let url = queue.removeFirst()
        let name = url.lastPathComponent
        Task {
            do {
                if url.pathExtension.lowercased() == "apk" {
                    status = "Installing \(name)…"
                    let out = try await adb.run(serial: serial, arguments: ["install", "-r", url.path], timeout: .seconds(600))
                    let text = String(decoding: out.stdout, as: UTF8.self)
                    status = text.contains("Success") ? "Installed \(name)" : "Install failed: " + (text.split(separator: "\n").last.map(String.init) ?? "unknown error")
                } else if ["xapk", "apks", "aab"].contains(url.pathExtension.lowercased()) {
                    status = "\(name): split packages are not supported yet, drop a plain .apk"
                } else {
                    status = "Copying \(name) to Download…"
                    _ = try await adb.run(serial: serial, arguments: ["push", url.path, "/sdcard/Download/\(name)"], timeout: .seconds(3600))
                    status = "Copied \(name) to /sdcard/Download"
                }
            } catch { status = "\(name): \(error.localizedDescription)" }
            processNext()
        }
    }

    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { status = nil } }
    }
}

struct DropOverlay: View {
    @ObservedObject var installer: DropInstaller
    var body: some View {
        ZStack(alignment: .bottom) {
            if installer.targeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 42))
                            Text("Drop an APK to install").font(.title3.weight(.semibold))
                            Text("Other files are copied to Download").font(.caption).foregroundStyle(.secondary)
                        }
                    )
                    .padding(14)
                    .allowsHitTesting(false)
            }
            if let status = installer.status {
                HStack(spacing: 8) {
                    if installer.busy { ProgressView().controlSize(.small) }
                    Text(status).font(.callout).lineLimit(2)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .allowsHitTesting(false)
            }
        }
    }
}
