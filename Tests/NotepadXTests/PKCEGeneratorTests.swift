import XCTest
@testable import NotepadX

final class PKCEGeneratorTests: XCTestCase {
    func testCodeVerifierUsesOnlyURLSafeCharacters() {
        let verifier = PKCEGenerator.generateCodeVerifier()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertGreaterThanOrEqual(verifier.count, 32)
    }

    func testCodeVerifiersAreRandomPerCall() {
        let first = PKCEGenerator.generateCodeVerifier()
        let second = PKCEGenerator.generateCodeVerifier()
        XCTAssertNotEqual(first, second)
    }

    func testCodeChallengeIsDeterministicForSameVerifier() {
        let verifier = "fixed-verifier-value-for-testing"
        let challengeA = PKCEGenerator.codeChallenge(for: verifier)
        let challengeB = PKCEGenerator.codeChallenge(for: verifier)
        XCTAssertEqual(challengeA, challengeB)
        // Base64URL이라 표준 base64의 +, /, = 패딩이 나오면 안 된다.
        XCTAssertFalse(challengeA.contains("+"))
        XCTAssertFalse(challengeA.contains("/"))
        XCTAssertFalse(challengeA.contains("="))
    }

    func testCodeChallengeDiffersForDifferentVerifiers() {
        let challengeA = PKCEGenerator.codeChallenge(for: "verifier-one")
        let challengeB = PKCEGenerator.codeChallenge(for: "verifier-two")
        XCTAssertNotEqual(challengeA, challengeB)
    }

    func testStateIsRandomPerCall() {
        let first = PKCEGenerator.generateState()
        let second = PKCEGenerator.generateState()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }
}
