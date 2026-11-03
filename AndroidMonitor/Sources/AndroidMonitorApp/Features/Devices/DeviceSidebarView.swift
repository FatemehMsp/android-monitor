import SwiftUI

struct DeviceSidebarView: View {
    let devices: [AndroidDevice]
    let activeSerial: String?
    let select: (AndroidDevice) -> Void

    var body: some View {
        List(devices, selection: .constant(activeSerial)) { device in
            Button { select(device) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.model ?? device.serial)
                    Text(device.state.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(device.state == .device ? Color.secondary : Color.orange)
                }
            }
            .buttonStyle(.plain)
            .disabled(device.state != .device)
            .tag(device.serial)
        }
        .navigationTitle("Devices")
    }
}
