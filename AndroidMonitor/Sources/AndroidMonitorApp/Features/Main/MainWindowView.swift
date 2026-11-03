import SwiftUI

struct MainWindowView: View {
    @State private var devices: [AndroidDevice] = []
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward").font(.title3).foregroundStyle(Theme.gradient)
                        Text("Android Monitor").font(.headline)
                    }
                    .padding(.bottom, 4)
                    Text("DEVICES · \(devices.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(devices) { device in
                        DeviceRow(device: device, selected: selection == device.serial)
                            .onTapGesture { if device.state == .device { selection = device.serial } }
                    }
                }
                .padding(12)
            }
            .background(Theme.backdrop.opacity(0.55))
            .safeAreaInset(edge: .bottom) {
                Button { PairingWindowController.shared.show() } label: {
                    Label("Pair over Wi-Fi", systemImage: "wifi").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent2)
                .controlSize(.large)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            .overlay {
                if devices.isEmpty {
                    ContentUnavailableView("No devices", systemImage: "iphone.slash", description: Text("Plug in a phone and enable USB debugging."))
                }
            }
        } detail: {
            if let device = devices.first(where: { $0.serial == selection }), device.state == .device {
                DeviceWorkspaceView(device: device).id(device.serial)
            } else {
                ContentUnavailableView(
                    "Select a device",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    description: Text("USB and Wireless Debugging are supported.")
                )
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                let latest = await Task.detached { DeviceSnapshot.load() }.value
                if latest != devices { devices = latest }
                if selection == nil || !latest.contains(where: { $0.serial == selection }) {
                    selection = latest.first(where: { $0.state == .device })?.serial
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice
    let selected: Bool
    private var isWireless: Bool { device.serial.contains(":") || device.serial.contains("_adb-tls") }
    private var ready: Bool { device.state == .device }

    var body: some View {
        Card(selected: selected) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: isWireless ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                        .font(.title2).foregroundStyle(ready ? Theme.accent : Color.orange).frame(width: 28)
                    Circle().fill(ready ? Color.green : Color.orange).frame(width: 8, height: 8).offset(x: 3, y: 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.model ?? device.serial).font(.body.weight(.semibold)).lineLimit(1)
                    Text(ready ? (isWireless ? "Wi-Fi · \(device.serial)" : "USB · \(device.serial)") : device.state.rawValue.capitalized)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .opacity(ready ? 1 : 0.6)
        .contentShape(Rectangle())
    }
}

enum DeviceSnapshot {
    static func load() -> [AndroidDevice] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = AppADB.url
        process.arguments = ["devices", "-l"]
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? ADBOutputParser.devices(String(decoding: data, as: UTF8.self))) ?? []
    }
}
