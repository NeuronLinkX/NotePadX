import Foundation

/// DOCX(OOXML)는 결국 ZIP 컨테이너다. ZipFoundation 같은 외부 의존성을 추가하는 대신
/// store(비압축) 방식의 최소 ZIP 라이터를 직접 구현한다 — 표준 ZIP 리더(Word, LibreOffice,
/// Finder, unzip)는 압축을 강제하지 않고 store 항목도 정상적으로 읽는다.
struct ZipArchiveWriter {
    private struct Entry {
        let path: String
        let byteCount: Int
        let crc32: UInt32
        let localHeaderOffset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private var body = Data()
    private var entries: [Entry] = []

    mutating func addFile(path: String, data: Data, date: Date = Date()) {
        let crc = CRC32.checksum(data)
        let offset = UInt32(body.count)
        let (dosTime, dosDate) = Self.dosDateTime(from: date)

        body.append(Self.localFileHeader(path: path, byteCount: data.count, crc: crc, dosTime: dosTime, dosDate: dosDate))
        body.append(data)

        entries.append(Entry(path: path, byteCount: data.count, crc32: crc, localHeaderOffset: offset, dosTime: dosTime, dosDate: dosDate))
    }

    func finalize() -> Data {
        var result = body
        let centralDirStart = UInt32(result.count)

        for entry in entries {
            result.append(Self.centralDirectoryHeader(entry: entry))
        }
        let centralDirSize = UInt32(result.count) - centralDirStart

        result.append(Self.endOfCentralDirectory(
            entryCount: entries.count,
            centralDirSize: centralDirSize,
            centralDirStart: centralDirStart
        ))
        return result
    }

    // MARK: - 레코드 인코딩

    private static func localFileHeader(path: String, byteCount: Int, crc: UInt32, dosTime: UInt16, dosDate: UInt16) -> Data {
        var d = Data()
        let nameData = Data(path.utf8)
        d.appendLE32(0x0403_4b50)
        d.appendLE16(20)
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE16(dosTime)
        d.appendLE16(dosDate)
        d.appendLE32(crc)
        d.appendLE32(UInt32(byteCount))
        d.appendLE32(UInt32(byteCount))
        d.appendLE16(UInt16(nameData.count))
        d.appendLE16(0)
        d.append(nameData)
        return d
    }

    private static func centralDirectoryHeader(entry: Entry) -> Data {
        var d = Data()
        let nameData = Data(entry.path.utf8)
        d.appendLE32(0x0201_4b50)
        d.appendLE16(20)
        d.appendLE16(20)
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE16(entry.dosTime)
        d.appendLE16(entry.dosDate)
        d.appendLE32(entry.crc32)
        d.appendLE32(UInt32(entry.byteCount))
        d.appendLE32(UInt32(entry.byteCount))
        d.appendLE16(UInt16(nameData.count))
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE32(0)
        d.appendLE32(entry.localHeaderOffset)
        d.append(nameData)
        return d
    }

    private static func endOfCentralDirectory(entryCount: Int, centralDirSize: UInt32, centralDirStart: UInt32) -> Data {
        var d = Data()
        d.appendLE32(0x0605_4b50)
        d.appendLE16(0)
        d.appendLE16(0)
        d.appendLE16(UInt16(entryCount))
        d.appendLE16(UInt16(entryCount))
        d.appendLE32(centralDirSize)
        d.appendLE32(centralDirStart)
        d.appendLE16(0)
        return d
    }

    private static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let year = UInt16(max(0, (components.year ?? 1980) - 1980))
        let month = UInt16(components.month ?? 1)
        let day = UInt16(components.day ?? 1)
        let hour = UInt16(components.hour ?? 0)
        let minute = UInt16(components.minute ?? 0)
        let second = UInt16(components.second ?? 0)

        let dosDate = (year << 9) | (month << 5) | day
        let dosTime = (hour << 11) | (minute << 5) | (second / 2)
        return (dosTime, dosDate)
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
