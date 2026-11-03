import SwiftUI

struct DeviceWorkspaceView: View {
    let device: AndroidDevice
    @AppStorage("mirrorEnabled") private var mirrorEnabled = true
    @StateObject private var installer: DropInstaller

    init(device: AndroidDevice) {
        self.device = device
        _installer = StateObject(wrappedValue: DropInstaller(serial: device.serial))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.model ?? device.serial).font(.headline)
                        Text(device.serial).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    DeviceKeyButton(icon: "chevron.backward", help: "Back", code: 4, tint: Theme.accent, serial: device.serial)
                    DeviceKeyButton(icon: "circle", help: "Home", code: 3, tint: Theme.accent2, serial: device.serial)
                    DeviceKeyButton(icon: "square.on.square", help: "Recents", code: 187, tint: .purple, serial: device.serial)
                    DeviceKeyButton(icon: "power", help: "Power", code: 26, tint: .orange, serial: device.serial)
                    Divider().frame(height: 18).padding(.horizontal, 2)
                    IconButton(icon: mirrorEnabled ? "eye.fill" : "eye.slash.fill", help: mirrorEnabled ? "Mirror on (click to turn off and save memory)" : "Mirror off (click to turn on)", tint: mirrorEnabled ? Theme.accent : .gray) { mirrorEnabled.toggle() }
                    IconButton(icon: "camera.fill", help: "Screenshot", tint: Theme.accent2) { DeviceActions.screenshot(serial: device.serial) }
                    IconButton(icon: "record.circle", help: "Start recording", tint: .red) { DeviceActions.startRecording(serial: device.serial) }
                    IconButton(icon: "stop.circle", help: "Stop recording", tint: .gray) { DeviceActions.stopRecording(serial: device.serial) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
                Divider()
                ZStack {
                    Theme.backdrop
                    if mirrorEnabled {
                        H264MirrorView(serial: device.serial)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
                            .shadow(color: Theme.accent.opacity(0.25), radius: 24)
                            .padding(18)
                    } else {
                        ContentUnavailableView {
                            Label("Mirror is off", systemImage: "eye.slash")
                        } description: {
                            Text("Files, Apps, Logcat and Shell still work. Turning the mirror off saves memory and CPU.")
                        } actions: {
                            Button("Turn on Mirror") { mirrorEnabled = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .frame(minWidth: 380, idealWidth: 460)
            InspectorPanels(serial: device.serial)
                .frame(minWidth: 420)
        }
        .onDrop(of: [.fileURL], isTargeted: $installer.targeted) { installer.accept($0) }
        .overlay { DropOverlay(installer: installer) }
    }
}

private struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DeviceKeyButton: View {
    let icon: String
    let help: String
    let code: Int
    let tint: Color
    let serial: String
    var body: some View {
        IconButton(icon: icon, help: help, tint: tint) {
            Task {
                let adb = ADBClient(adbURL: AppADB.url)
                _ = try? await adb.run(serial: serial, arguments: ["shell", "input", "keyevent", "\(code)"], timeout: .seconds(5))
            }
        }
    }
}
