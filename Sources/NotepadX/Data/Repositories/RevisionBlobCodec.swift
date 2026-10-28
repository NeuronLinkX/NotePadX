import CryptoKit
import Foundation

/// 버전 기록 JSON 안의 큰 인라인 이미지(`data:image/...;base64,...`)를 짧은 해시 참조로 바꾸고,
/// 필요할 때 원래 문자열로 되돌린다. JSON을 해석하지 않고 **문자열 그대로** 치환하므로, 되돌린 결과는
/// 원본과 한 글자도 다르지 않다(키 순서·이스케이프·숫자 표기가 바뀔 일이 없다).
enum RevisionBlobCodec {
    static let referencePrefix = "notepadx-blob:"
    /// 아이콘처럼 작은 이미지는 그대로 둔다 — 참조로 바꿔도 얻는 게 없고 조회만 번거로워진다.
    static let minimumLength = 2048

    private static let referenceRegex = try! NSRegularExpression(pattern: "notepadx-blob:([0-9a-f]{64})")

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let needle = Array("data:image".utf8)
    private static let base64Marker = Array(";base64,".utf8)

    /// 큰 이미지를 참조로 바꾼 JSON과, 해시 → 원본 문자열 사전을 돌려준다. 바꿀 게 없으면 blobs가 비어 있다.
    ///
    /// 정규식을 쓰지 않고 바이트를 직접 훑는다. 실제 사진은 base64로 수 MB인데, 정규식 엔진(ICU)은
    /// 그렇게 긴 반복에서 스택 한도에 걸려 **오류도 없이 "일치 없음"을 돌려준다** — 작은 테스트
    /// 이미지에서는 멀쩡하다가 실제 데이터에서만 조용히 실패하는 종류의 버그라서 피한다.
    static func extract(from json: String) -> (compacted: String, blobs: [String: String]) {
        let bytes = Array(json.utf8)
        var output: [UInt8] = []
        var blobs: [String: String] = [:]
        var copiedUpTo = 0
        var cursor = 0

        while let start = find(needle, in: bytes, from: cursor) {
            guard let end = endOfDataURI(in: bytes, startingAt: start), end - start >= minimumLength else {
                cursor = start + needle.count
                continue
            }
            let matched = bytes[start..<end]
            let hash = SHA256.hash(data: matched).map { String(format: "%02x", $0) }.joined()
            blobs[hash] = String(decoding: matched, as: UTF8.self)
            if output.isEmpty { output.reserveCapacity(bytes.count / 4) }
            output.append(contentsOf: bytes[copiedUpTo..<start])
            output.append(contentsOf: Array((referencePrefix + hash).utf8))
            copiedUpTo = end
            cursor = end
        }
        guard !blobs.isEmpty else { return (json, [:]) }
        output.append(contentsOf: bytes[copiedUpTo...])
        return (String(decoding: output, as: UTF8.self), blobs)
    }

    /// `data:image/<종류>;base64,<본문>`이 끝나는 위치. 슬래시는 JSON 인코더에 따라 `\/`로
    /// 이스케이프돼 있을 수 있다. 형식이 맞지 않으면 nil.
    private static func endOfDataURI(in bytes: [UInt8], startingAt start: Int) -> Int? {
        let slash = UInt8(ascii: "/"), backslash = UInt8(ascii: "\\")
        var p = start + needle.count
        if p < bytes.count, bytes[p] == backslash { p += 1 }
        guard p < bytes.count, bytes[p] == slash else { return nil }
        p += 1

        let mimeStart = p
        while p < bytes.count, isMimeByte(bytes[p]) { p += 1 }
        guard p > mimeStart, p + base64Marker.count <= bytes.count,
              Array(bytes[p..<(p + base64Marker.count)]) == base64Marker else { return nil }
        p += base64Marker.count

        let payloadStart = p
        while p < bytes.count {
            let byte = bytes[p]
            if isBase64Byte(byte) {
                p += 1
            } else if byte == backslash, p + 1 < bytes.count, bytes[p + 1] == slash {
                p += 2
            } else {
                break
            }
        }
        return p > payloadStart ? p : nil
    }

    private static func isBase64Byte(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2B || b == 0x2F || b == 0x3D
    }

    private static func isMimeByte(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2E || b == 0x2B || b == 0x2D
    }

    private static func find(_ pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes.withUnsafeBufferPointer { buffer -> Int? in
            guard let base = buffer.baseAddress,
                  let hit = memmem(base + start, buffer.count - start, pattern, pattern.count) else { return nil }
            return base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
        }
    }

    static func referencedHashes(in json: String) -> [String] {
        let source = json as NSString
        return referenceRegex.matches(in: json, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
    }

    /// 참조를 원래 이미지 문자열로 되돌린다. 사전에 없는 참조(블롭이 사라진 경우)는 그대로 둔다.
    static func hydrate(_ json: String, lookup: (String) -> String?) -> String {
        let source = json as NSString
        let matches = referenceRegex.matches(in: json, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return json }

        var result = ""
        var cursor = 0
        for match in matches {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let hash = source.substring(with: match.range(at: 1))
            result += lookup(hash) ?? source.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    // MARK: - 저장 형식

    /// 1바이트 머리글(0 = 그대로, 1 = LZFSE 압축) + 본문. base64는 압축해도 ~25%만 줄지만 공짜다.
    static func encodeForStorage(_ text: String) -> Data {
        let raw = Data(text.utf8)
        if let compressed = try? (raw as NSData).compressed(using: .lzfse) as Data, compressed.count < raw.count {
            return Data([1]) + compressed
        }
        return Data([0]) + raw
    }

    static func decodeFromStorage(_ data: Data) -> String? {
        guard let marker = data.first else { return nil }
        let body = data.dropFirst()
        switch marker {
        case 0:
            return String(data: body, encoding: .utf8)
        case 1:
            guard let raw = try? (Data(body) as NSData).decompressed(using: .lzfse) as Data else { return nil }
            return String(data: raw, encoding: .utf8)
        default:
            return nil
        }
    }
}
