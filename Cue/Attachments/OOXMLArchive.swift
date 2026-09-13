import Compression
import Foundation

nonisolated enum OOXMLArchiveError: LocalizedError, Equatable {
    case notZip
    case corrupt(String)
    case unsupportedCompression(Int)
    case entryMissing(String)

    var errorDescription: String? {
        switch self {
        case .notZip: "The file is not a ZIP archive."
        case .corrupt(let detail): "The archive is damaged (\(detail))."
        case .unsupportedCompression(let method): "Unsupported ZIP compression method \(method)."
        case .entryMissing(let name): "The archive has no \(name)."
        }
    }
}

/// Minimal read-only ZIP container for Office Open XML (`.docx`, `.xlsx`, `.pptx`) packages.
/// Walks the central directory and inflates entries with the Compression framework, so Cue
/// needs no third-party archive library. Zip64 and encryption are out of scope (Office never
/// writes them for documents under 4 GB).
nonisolated struct OOXMLArchive: Sendable {
    struct Entry: Sendable, Equatable {
        var name: String
        var method: Int
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    private static let centralFileHeader: UInt32 = 0x0201_4b50
    private static let localFileHeader: UInt32 = 0x0403_4b50

    let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    var names: [String] { entries.map(\.name) }

    func contains(_ name: String) -> Bool {
        entries.contains { $0.name == name }
    }

    /// Entry names under a directory prefix, e.g. `ppt/slides/`, excluding nested folders.
    func names(withPrefix prefix: String) -> [String] {
        entries.map(\.name).filter { name in
            name.hasPrefix(prefix) && !name.dropFirst(prefix.count).contains("/")
        }
    }

    func data(forEntry name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw OOXMLArchiveError.entryMissing(name)
        }
        return try inflate(entry)
    }

    func string(forEntry name: String) throws -> String {
        String(decoding: try data(forEntry: name), as: UTF8.self)
    }

    private func inflate(_ entry: Entry) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, data.readUInt32(at: base) == Self.localFileHeader else {
            throw OOXMLArchiveError.corrupt("local header for \(entry.name)")
        }
        let nameLength = Int(data.readUInt16(at: base + 26))
        let extraLength = Int(data.readUInt16(at: base + 28))
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { throw OOXMLArchiveError.corrupt("payload for \(entry.name)") }
        let payload = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return payload
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            return try Self.inflateRawDeflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw OOXMLArchiveError.unsupportedCompression(entry.method)
        }
    }

    /// `COMPRESSION_ZLIB` in the Compression framework is raw DEFLATE (RFC 1951), which is what ZIP stores.
    private static func inflateRawDeflate(_ payload: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(destinationBase, expectedSize, sourceBase, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw OOXMLArchiveError.corrupt("inflate produced \(written) of \(expectedSize) bytes") }
        return output
    }

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw OOXMLArchiveError.notZip }
        // The EOCD record sits at the very end, followed only by an optional comment (≤ 64 KB).
        let searchFloor = max(0, data.count - 22 - 65_535)
        var eocd = -1
        var cursor = data.count - 22
        while cursor >= searchFloor {
            if data.readUInt32(at: cursor) == endOfCentralDirectory {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard eocd >= 0 else { throw OOXMLArchiveError.notZip }

        let entryCount = Int(data.readUInt16(at: eocd + 10))
        let directorySize = Int(data.readUInt32(at: eocd + 12))
        let directoryOffset = Int(data.readUInt32(at: eocd + 16))
        guard directoryOffset + directorySize <= data.count else {
            throw OOXMLArchiveError.corrupt("central directory bounds")
        }

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var position = directoryOffset
        for _ in 0..<entryCount {
            guard position + 46 <= data.count, data.readUInt32(at: position) == centralFileHeader else {
                throw OOXMLArchiveError.corrupt("central directory entry")
            }
            let method = Int(data.readUInt16(at: position + 10))
            let compressedSize = Int(data.readUInt32(at: position + 20))
            let uncompressedSize = Int(data.readUInt32(at: position + 24))
            let nameLength = Int(data.readUInt16(at: position + 28))
            let extraLength = Int(data.readUInt16(at: position + 30))
            let commentLength = Int(data.readUInt16(at: position + 32))
            let localOffset = Int(data.readUInt32(at: position + 42))
            let nameStart = position + 46
            guard nameStart + nameLength <= data.count else { throw OOXMLArchiveError.corrupt("entry name") }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)), as: UTF8.self)
            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            position = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
