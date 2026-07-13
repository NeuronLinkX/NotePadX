import XCTest
@testable import NotepadX

final class ZipArchiveWriterTests: XCTestCase {
    func testUnzipCanExtractWrittenEntries() throws {
        var writer = ZipArchiveWriter()
        writer.addFile(path: "hello.txt", data: Data("Hello, NotepadX!".utf8))
        writer.addFile(path: "dir/nested.txt", data: Data("nested content".utf8))
        let zipData = writer.finalize()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("test.zip")
        try zipData.write(to: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", tempDir.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let extractedHello = try String(contentsOf: tempDir.appendingPathComponent("hello.txt"), encoding: .utf8)
        XCTAssertEqual(extractedHello, "Hello, NotepadX!")

        let extractedNested = try String(contentsOf: tempDir.appendingPathComponent("dir/nested.txt"), encoding: .utf8)
        XCTAssertEqual(extractedNested, "nested content")
    }

    func testCRC32MatchesKnownValue() {
        // "123456789"의 CRC-32 값은 표준 테스트 벡터로 0xCBF43926이다.
        let crc = CRC32.checksum(Data("123456789".utf8))
        XCTAssertEqual(crc, 0xCBF4_3926)
    }
}
