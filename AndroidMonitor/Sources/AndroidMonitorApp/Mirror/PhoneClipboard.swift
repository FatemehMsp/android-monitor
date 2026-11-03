import Foundation

/// Talks to `ClipHelper` (Scripts/cliphelper) running on the phone, so copy/cut/paste carry full Unicode text both ways.
@MainActor
final class PhoneClipboard {
    private let serial: String
    private var process: Process?
    private var input: FileHandle?
    private var mailbox: LineBuffer?
    private var starting: Task<Bool, Never>?

    init(serial: String) { self.serial = serial }

    func stop() { process?.terminate(); process = nil; input = nil; mailbox = nil; starting = nil }

    func get() async -> String? {
        guard let reply = await request("G"), reply.hasPrefix("G ") else { return nil }
        guard let data = Data(base64Encoded: String(reply.dropFirst(2))) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func set(_ text: String) async -> Bool {
        await request("S " + Data(text.utf8).base64EncodedString()) == "OK"
    }

    private var busy = false

    private func request(_ command: String) async -> String? {
        while busy { try? await Task.sleep(for: .milliseconds(5)) }   // one request/reply at a time
        busy = true
        defer { busy = false }
        if process?.isRunning != true {
            let task = starting ?? Task { await self.launch() }
            starting = task
            let ok = await task.value
            starting = nil
            guard ok else { return nil }
        }
        guard let input else { return nil }
        try? input.write(contentsOf: Data((command + "\n").utf8))
        var reply: String?
        for _ in 0..<300 {
            if let line = mailbox?.next() { reply = line; break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if reply == nil { stop() }
        return reply
    }

    private func launch() async -> Bool {
        guard let jar = Bundle.main.url(forResource: "amclip", withExtension: "jar") else { return false }
        let adb = ADBClient(adbURL: AppADB.url)
        guard (try? await adb.run(serial: serial, arguments: ["push", jar.path, "/data/local/tmp/amclip.jar"], timeout: .seconds(20))) != nil else { return false }

        let stdin = Pipe(), stdout = Pipe()
        let p = Process()
        p.executableURL = AppADB.url
        p.arguments = ["-s", serial, "shell", "CLASSPATH=/data/local/tmp/amclip.jar", "app_process", "/", "ClipHelper"]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice

        let buffer = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { buffer.append(chunk) }
        }
        guard (try? p.run()) != nil else { return false }
        process = p; input = stdin.fileHandleForWriting; mailbox = buffer
        return true
    }
}

/// Splits a byte stream into lines; filled from the pipe's background callback, drained on the main actor.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private var ready: [String] = []
    private let lock = NSLock()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        while let newline = data.firstIndex(of: 10) {
            ready.append(String(decoding: data[..<newline], as: UTF8.self))
            data.removeSubrange(...newline)
        }
    }
    func next() -> String? {
        lock.lock(); defer { lock.unlock() }
        return ready.isEmpty ? nil : ready.removeFirst()
    }
}
