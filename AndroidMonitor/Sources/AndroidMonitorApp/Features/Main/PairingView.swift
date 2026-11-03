import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct MDNSService: Identifiable, Hashable {
    let name: String
    let host: String
    let port: Int
    var id: String { "\(name)@\(host):\(port)" }
}

@MainActor
final class PairingModel: ObservableObject {
    @Published var pairingServices: [MDNSService] = []
    @Published var connectServices: [MDNSService] = []
    @Published var status = "Waiting for the phone…"
    @Published var working = false
    @Published var connected = false

    let qrName = "ADB_WIFI_" + String(Int.random(in: 1000...9999))
    let qrPassword = String(Int.random(in: 100_000...999_999))
    var qrPayload: String { "WIFI:T:ADB;S:\(qrName);P:\(qrPassword);;" }

    private var poll: Task<Void, Never>?
    private let service = PairingService(adbURL: AppADB.url)

    func start() {
        poll = Task {
            while !Task.isCancelled {
                let found = await Task.detached { Self.discover() }.value
                pairingServices = found.filter { $0.type.contains("pairing") }.map(\.service)
                connectServices = found.filter { $0.type.contains("connect") }.map(\.service)
                if let match = pairingServices.first(where: { $0.name == qrName }), !working, !connected {
                    await pair(match, code: qrPassword)
                }
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    func stop() { poll?.cancel() }

    nonisolated private static func discover() -> [(service: MDNSService, type: String)] {
        let p = Process(), pipe = Pipe()
        p.executableURL = AppADB.url; p.arguments = ["mdns", "services"]; p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let f = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard f.count >= 3, let colon = f[2].lastIndex(of: ":"), let port = Int(f[2][f[2].index(after: colon)...]) else { return nil }
            return (MDNSService(name: f[0], host: String(f[2][..<colon]), port: port), f[1])
        }
    }

    func pair(_ target: MDNSService, code: String) async {
        working = true; status = "Pairing with \(target.host)…"
        defer { working = false }
        do {
            try await service.pair(host: target.host, port: target.port, code: code)
            status = "Paired. Connecting…"
            for _ in 0..<8 {
                if let c = connectServices.first(where: { $0.host == target.host }) {
                    try await service.connect(host: c.host, port: c.port)
                    status = "Connected to \(c.host):\(c.port)"; connected = true; return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            status = "Paired. Now open the \"By IP\" tab and connect with the IP & port from the main Wireless debugging screen."
        } catch { status = "Pairing failed: wrong code or the pairing dialog closed on the phone." }
    }

    /// No mDNS and no pairing needed: while the phone is on USB, switch adbd to TCP and connect to its Wi-Fi IP.
    func switchUSBToWiFi() async {
        working = true; defer { working = false }
        let adb = ADBClient(adbURL: AppADB.url)
        let devices = await Task.detached { DeviceSnapshot.load() }.value
        guard let phone = devices.first(where: { $0.state == .device && !$0.serial.contains(":") && !$0.serial.contains("_adb-tls") }) else {
            status = "Plug the phone in with USB first (USB debugging on), then try again."; return
        }
        status = "Reading the phone's Wi-Fi address…"
        let out = (try? await adb.run(serial: phone.serial, arguments: ["shell", "ip", "-f", "inet", "addr", "show", "wlan0"], timeout: .seconds(10)).stdout) ?? Data()
        let text = String(decoding: out, as: UTF8.self)
        guard let range = text.range(of: #"inet (\d+\.\d+\.\d+\.\d+)"#, options: .regularExpression) else {
            status = "The phone has no Wi-Fi address. Connect it to the same Wi-Fi as this Mac."; return
        }
        let ip = String(text[range].dropFirst(5))
        status = "Switching \(phone.model ?? phone.serial) to Wi-Fi (\(ip))…"
        _ = try? await adb.run(serial: phone.serial, arguments: ["tcpip", "5555"], timeout: .seconds(15))
        try? await Task.sleep(for: .seconds(2))
        do {
            try await service.connect(host: ip, port: 5555)
            status = "Connected to \(ip):5555. You can unplug the cable."; connected = true
        } catch { status = "Could not reach \(ip):5555. The Mac and phone may be on different networks, or a VPN is in the way." }
    }

    func connectManually(host: String, port: Int) async {
        working = true; defer { working = false }
        do { try await service.connect(host: host, port: port); status = "Connect requested for \(host):\(port)" }
        catch { status = error.localizedDescription }
    }
}

struct PairingView: View {
    @StateObject private var model = PairingModel()
    @State private var mode = 0
    @State private var pairHost = ""
    @State private var pairPort = ""
    @State private var code = ""
    @State private var selected: MDNSService?
    @State private var manualHost = ""
    @State private var manualPort = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) { Text("Via USB").tag(0); Text("QR code").tag(1); Text("Pairing code").tag(2); Text("By IP").tag(3) }
                .pickerStyle(.segmented).labelsHidden()
            switch mode {
            case 0: usb
            case 1: qr
            case 2: codePairing
            default: manual
            }
            Divider()
            HStack {
                if model.working { ProgressView().controlSize(.small) }
                Image(systemName: model.connected ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.connected ? Theme.accent : .secondary)
                Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 400)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .preferredColorScheme(.dark).tint(Theme.accent)
    }

    private var usb: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The most reliable way: keep the phone plugged in once, and it switches to Wi-Fi by itself. No pairing, no codes, no mDNS.")
                .font(.callout).foregroundStyle(.secondary)
            Button { Task { await model.switchUSBToWiFi() } } label: {
                Label("Switch USB phone to Wi-Fi", systemImage: "cable.connector.horizontal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.working)
            Text("Needs the phone and this Mac on the same network.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var qr: some View {
        VStack(spacing: 10) {
            if let image = Self.qrImage(model.qrPayload) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 180, height: 180)
                    .padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("On the phone: Developer options → Wireless debugging → **Pair device with QR code**, then scan. Nothing else to type.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var codePairing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open **Pair device with pairing code** on the phone. It appears here automatically.").font(.callout).foregroundStyle(.secondary)
            if model.pairingServices.isEmpty {
                Text("Nothing found automatically. Some Wi-Fi networks (office, VPN) block discovery. Enter the IP and pairing port shown on the phone instead:")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("IP", text: $pairHost).textFieldStyle(.roundedBorder)
                    TextField("Pairing port", text: $pairPort).textFieldStyle(.roundedBorder).frame(width: 100)
                }
            }
            ForEach(model.pairingServices) { item in
                Card(selected: selected == item) {
                    HStack { Image(systemName: "iphone.gen3"); Text(item.host); Spacer(); Text("port \(item.port)").foregroundStyle(.secondary) }
                }.onTapGesture { selected = item }
            }
            HStack {
                TextField("6-digit code", text: $code).textFieldStyle(.roundedBorder)
                Button("Pair") {
                    if let target = selected ?? model.pairingServices.first {
                        Task { await model.pair(target, code: code); code = "" }
                    } else if let port = Int(pairPort) {
                        Task { await model.pair(MDNSService(name: "manual", host: pairHost, port: port), code: code); code = "" }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 6 || model.working || (model.pairingServices.isEmpty && (pairHost.isEmpty || Int(pairPort) == nil)))
            }
        }
    }

    private var manual: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already paired before? Phones on the same Wi-Fi that are paired show up on their own. If not, enter the IP and the port from the Wireless debugging screen.")
                .font(.callout).foregroundStyle(.secondary)
            if !model.connectServices.isEmpty {
                ForEach(model.connectServices) { item in
                    Button { Task { await model.connectManually(host: item.host, port: item.port) } } label: {
                        Label("Connect \(item.host):\(item.port)", systemImage: "wifi").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
            HStack {
                TextField("IP", text: $manualHost).textFieldStyle(.roundedBorder)
                TextField("Port", text: $manualPort).textFieldStyle(.roundedBorder).frame(width: 80)
                Button("Connect") { if let port = Int(manualPort) { Task { await model.connectManually(host: manualHost, port: port) } } }
                    .buttonStyle(.borderedProminent).disabled(manualHost.isEmpty || Int(manualPort) == nil)
            }
        }
    }

    private static func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size); image.addRepresentation(rep)
        return image
    }
}
