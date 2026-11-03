import Foundation

public struct AnnexBParser: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        let starts = startCodes(in: buffer)
        guard starts.count >= 2 else { return [] }
        var units: [Data] = []
        for index in 0..<(starts.count - 1) {
            let start = starts[index].offset + starts[index].length
            let end = starts[index + 1].offset
            if start < end { units.append(buffer.subdata(in: start..<end)) }
        }
        buffer.removeSubrange(0..<starts.last!.offset)
        return units
    }

    /// Emits the unit still buffered after the stream has gone quiet, so the newest frame is not held back.
    /// A unit split across a >30ms pipe stall would be cut short; that costs one glitched frame at most.
    public mutating func finishTrailingUnit() -> [Data] {
        guard let start = startCodes(in: buffer).first else { return [] }
        let offset = start.offset + start.length
        guard offset < buffer.count else { return [] }
        let unit = buffer.subdata(in: offset..<buffer.count)
        buffer.removeAll()
        return [unit]
    }

    public mutating func finish() -> [Data] {
        guard let start = startCodes(in: buffer).first else { buffer.removeAll(); return [] }
        let offset = start.offset + start.length
        defer { buffer.removeAll() }
        guard offset < buffer.count else { return [] }
        return [buffer.subdata(in: offset..<buffer.count)]
    }

    private func startCodes(in data: Data) -> [(offset: Int, length: Int)] {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return [] }
        var result: [(Int, Int)] = []
        var index = 0
        while index + 2 < bytes.count {
            if index + 3 < bytes.count, bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                result.append((index, 4)); index += 4
            } else if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                result.append((index, 3)); index += 3
            } else {
                index += 1
            }
        }
        return result
    }
}

public struct H264NALUnit: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case nonIDRSlice = 1, idrSlice = 5, sequenceParameterSet = 7, pictureParameterSet = 8 }
    public let data: Data
    public let type: Kind?
    public init?(data: Data) {
        guard let first = data.first else { return nil }
        self.data = data
        self.type = Kind(rawValue: first & 0x1f)
    }
}
