import Compression
import Foundation

/// 가져오기용 최소 ZIP 리더. DOCX는 ZIP 컨테이너이고, Word가 저장한 항목은 거의 항상 deflate로 압축돼 있다
/// (`ZipArchiveWriter`가 만드는 store 항목도 읽는다). 외부 의존성 없이 중앙 디렉터리를 읽고, 항목마다 CRC를
/// 확인한다. 신뢰할 수 없는 파일을 열기 때문에 항목 크기에 상한을 둔다(압축 폭탄 방지).
struct ZipArchiveReader {
    enum ReadError: Error, Equatable {
        case notAZip
        case unsupportedCompression(UInt16)
        case encrypted
        case corrupted(String)
        case tooLarge(String)
    }

    struct Entry {
        let path: String
        let method: UInt16
        let flags: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// 항목 하나가 풀린 뒤 가질 수 있는 최대 크기.
    static let maxEntryBytes = 64 * 1024 * 1024

    private let data: Data
    private(set) var entries: [Entry]

    init(data: Data) throws {
        self.data = data
        guard let eocd = Self.findEndOfCentralDirectory(in: data) else { throw ReadError.notAZip }
        let count = Int(data.le16(eocd + 10))
        let size = Int(data.le32(eocd + 12))
        let offset = Int(data.le32(eocd + 16))
        guard offset >= 0, size >= 0, offset + size <= data.count else { throw ReadError.corrupted("중앙 디렉터리 범위") }

        var parsed: [Entry] = []
        var cursor = offset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.le32(cursor) == 0x0201_4b50 else { throw ReadError.corrupted("중앙 디렉터리 항목") }
            let flags = data.le16(cursor + 8)
            let method = data.le16(cursor + 10)
            let crc = data.le32(cursor + 16)
            let compressed = Int(data.le32(cursor + 20))
            let uncompressed = Int(data.le32(cursor + 24))
            let nameLength = Int(data.le16(cursor + 28))
            let extraLength = Int(data.le16(cursor + 30))
            let commentLength = Int(data.le16(cursor + 32))
            let localOffset = Int(data.le32(cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { throw ReadError.corrupted("파일 이름") }
            let nameBytes = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
            parsed.append(Entry(
                path: name, method: method, flags: flags, crc32: crc,
                compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        self.entries = parsed
    }

    func entry(at path: String) -> Entry? { entries.first { $0.path == path } }

    func contains(_ path: String) -> Bool { entry(at: path) != nil }

    /// 항목을 풀어 돌려준다. 없으면 nil.
    func read(_ path: String) throws -> Data? {
        guard let entry = entry(at: path) else { return nil }
        return try read(entry)
    }

    func read(_ entry: Entry) throws -> Data {
        if entry.flags & 0x1 != 0 { throw ReadError.encrypted }
        guard entry.uncompressedSize <= Self.maxEntryBytes else { throw ReadError.tooLarge(entry.path) }
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, data.le32(local) == 0x0403_4b50 else { throw ReadError.corrupted("로컬 헤더 \(entry.path)") }
        let nameLength = Int(data.le16(local + 26))
        let extraLength = Int(data.le16(local + 28))
        let start = local + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count, entry.compressedSize >= 0 else { throw ReadError.corrupted("항목 범위 \(entry.path)") }
        let payload = data.subdata(in: start..<end)

        let output: Data
        switch entry.method {
        case 0:
            output = payload
        case 8:
            output = try Self.inflate(payload, expectedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw ReadError.unsupportedCompression(entry.method)
        }
        guard output.count == entry.uncompressedSize else { throw ReadError.corrupted("크기 불일치 \(entry.path)") }
        guard CRC32.checksum(output) == entry.crc32 else { throw ReadError.corrupted("CRC 불일치 \(entry.path)") }
        return output
    }

    // MARK: - 내부

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        // 끝에서부터 서명을 찾는다(뒤에 주석이 붙을 수 있다).
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var index = data.count - 22
        while index >= lowest {
            if data.le32(index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    /// ZIP의 deflate는 헤더 없는 raw deflate이고, Apple `COMPRESSION_ZLIB`가 정확히 그 형식이다.
    private static func inflate(_ payload: Data, expectedSize: Int, path: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dest -> Int in
            payload.withUnsafeBytes { source -> Int in
                guard let d = dest.bindMemory(to: UInt8.self).baseAddress, let s = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, expectedSize, s, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ReadError.corrupted("압축 해제 실패 \(path)") }
        return output
    }
}

private extension Data {
    func le16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func le32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let b = startIndex + offset
        return UInt32(self[b]) | UInt32(self[b + 1]) << 8 | UInt32(self[b + 2]) << 16 | UInt32(self[b + 3]) << 24
    }
}
