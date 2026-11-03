import Foundation

public actor ActiveDeviceSession {
    public nonisolated let serial: String
    private let onClose: (@Sendable (String) async -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var closed = false

    public init(serial: String, onClose: (@Sendable (String) async -> Void)? = nil) {
        self.serial = serial
        self.onClose = onClose
    }

    public func register(_ task: Task<Void, Never>) {
        guard !closed else { task.cancel(); return }
        tasks[UUID()] = task
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        await onClose?(serial)
    }
}
