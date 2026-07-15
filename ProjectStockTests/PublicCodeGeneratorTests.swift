import XCTest
@testable import ProjectStock

final class PublicCodeGeneratorTests: XCTestCase {

    func testCodeFormatIs18AllowedCharacters() {
        let generator = PublicCodeGenerator()
        for _ in 0..<200 {
            let code = generator.generateCandidate()
            XCTAssertEqual(code.count, 18, "コードは18文字でなければならない")
            XCTAssertTrue(code.hasPrefix("IQ"))
            let body = code.dropFirst(2)
            let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
            XCTAssertTrue(body.allSatisfy { allowed.contains($0) }, "本体はCrockford Base32のみ: \(code)")
            XCTAssertTrue(PublicCodeGenerator.isValid(code))
        }
    }

    func testCrockfordAlphabetExcludesAmbiguousLetters() {
        let alphabet = Set(PublicCodeGenerator.alphabet)
        for ch in "ILOU" {
            XCTAssertFalse(alphabet.contains(ch), "紛らわしい文字 \(ch) は除外する")
        }
        XCTAssertEqual(PublicCodeGenerator.alphabet.count, 32)
    }

    func testInvalidCodesRejected() {
        XCTAssertFalse(PublicCodeGenerator.isValid("IQ123"))             // too short
        XCTAssertFalse(PublicCodeGenerator.isValid("XX0000000000000000")) // wrong prefix
        XCTAssertFalse(PublicCodeGenerator.isValid("IQ000000000000000I")) // I not in alphabet
    }

    /// Regeneration on collision is verified with scripted randomness (not a
    /// probabilistic test): same bytes → same code, so a forced duplicate must
    /// be skipped (spec §17).
    func testRegeneratesOnCollision() throws {
        let dup: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let other: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let provider = ScriptedRandomProvider([dup, dup, other])
        let generator = PublicCodeGenerator(random: provider)

        let firstCode = PublicCodeGenerator.prefix + PublicCodeGenerator.encodeBase32(dup, symbolCount: 16)
        var taken = Set([firstCode])
        let result = try generator.generateUnique(isTaken: { taken.contains($0) })
        XCTAssertFalse(taken.contains(result))
        XCTAssertGreaterThanOrEqual(provider.callCount, 2, "衝突時に再生成されるべき")
    }

    func testBatchProducesUniqueCodesDespiteDuplicateRandomness() throws {
        let a: [UInt8] = Array(repeating: 7, count: 10)
        let b: [UInt8] = Array(repeating: 9, count: 10)
        // a, a (duplicate), b -> batch of 2 should yield the two distinct codes.
        let provider = ScriptedRandomProvider([a, a, b])
        let generator = PublicCodeGenerator(random: provider)
        let codes = try generator.generateUniqueBatch(count: 2, isTaken: { _ in false })
        XCTAssertEqual(Set(codes).count, 2, "バッチ内のコードは一意でなければならない")
    }

    func testEightyBitsProduceSixteenSymbols() {
        let bytes = [UInt8](repeating: 0xFF, count: 10)
        let encoded = PublicCodeGenerator.encodeBase32(bytes, symbolCount: 16)
        XCTAssertEqual(encoded.count, 16)
        // 80 bits of 1s → all 'Z' (value 31) in Crockford.
        XCTAssertEqual(encoded, String(repeating: "Z", count: 16))
    }
}
