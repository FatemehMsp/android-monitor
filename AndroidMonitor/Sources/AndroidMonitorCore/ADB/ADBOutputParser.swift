import Foundation

public enum ADBOutputParser {
    public static func devices(_ text: String) throws -> [AndroidDevice] {
        try text.split(whereSeparator: \Character.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices attached") { return nil }
            let fields = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard fields.count >= 2 else { throw ADBParseError.malformedLine(line) }
            guard let state = DeviceState(rawValue: fields[1]) else {
                throw ADBParseError.unsupportedState(fields[1])
            }
            var metadata: [String: String] = [:]
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { metadata[pair[0]] = pair[1] }
            }
            return AndroidDevice(
                serial: fields[0],
                state: state,
                product: metadata["product"],
                model: metadata["model"],
                transportID: metadata["transport_id"]
            )
        }
    }
}

