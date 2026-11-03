import Foundation

@MainActor
public final class DeviceRegistry {
    public private(set) var devices: [AndroidDevice] = []
    public private(set) var lastError: String?
    private let adb: any ADBServing
    private var trackingTask: Task<Void, Never>?

    public init(adb: any ADBServing) { self.adb = adb }

    public func start() {
        guard trackingTask == nil else { return }
        trackingTask = Task { [weak self, adb] in
            do {
                for try await snapshot in adb.trackDevices() {
                    guard !Task.isCancelled else { return }
                    self?.devices = snapshot
                    self?.lastError = nil
                }
            } catch where error is CancellationError {
                return
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    public func stop() {
        trackingTask?.cancel()
        trackingTask = nil
    }
}
