import Foundation
import Security

/// Supplies random bytes. Abstracted so tests can inject deterministic bytes
/// (including forced collisions) to exercise the regeneration path.
public protocol RandomByteProviding {
    func randomBytes(count: Int) -> [UInt8]
}

/// Production implementation backed by `SecRandomCopyBytes` (spec §6).
public struct SecureRandomByteProvider: RandomByteProviding {
    public init() {}
    public func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return bytes
    }
}

public enum PublicCodeError: LocalizedError {
    case exhaustedAttempts(Int)
    public var errorDescription: String? {
        switch self {
        case .exhaustedAttempts(let n):
            return "一意なコードを\(n)回の試行で生成できませんでした。"
        }
    }
}

/// Generates the short, opaque QR payloads (`CodeAlias.publicCode`).
///
/// Format (spec §6): `IQ` + 16 Crockford-Base32 characters = 18 characters.
/// The 16-character body encodes 80 bits of cryptographically secure random
/// data (10 bytes → 16 × 5-bit symbols). The Crockford alphabet excludes the
/// visually ambiguous letters I, L, O and U.
public struct PublicCodeGenerator {

    public static let prefix = "IQ"
    public static let bodyLength = 16
    public static let totalLength = 18
    /// 80 bits of entropy → 10 bytes (spec: "80bit以上").
    public static let entropyByteCount = 10
    /// Crockford Base32 alphabet (no I, L, O, U).
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let alphabetSet = Set(alphabet)

    private let random: RandomByteProviding

    public init(random: RandomByteProviding = SecureRandomByteProvider()) {
        self.random = random
    }

    /// One random candidate code (no uniqueness check).
    public func generateCandidate() -> String {
        let bytes = random.randomBytes(count: Self.entropyByteCount)
        return Self.prefix + Self.encodeBase32(bytes, symbolCount: Self.bodyLength)
    }

    /// Generate a code that is not already present, regenerating on collision.
    /// - Parameter isTaken: returns `true` if a candidate already exists locally.
    public func generateUnique(maxAttempts: Int = 100,
                               isTaken: (String) -> Bool) throws -> String {
        for _ in 0..<maxAttempts {
            let candidate = generateCandidate()
            if !isTaken(candidate) { return candidate }
        }
        throw PublicCodeError.exhaustedAttempts(maxAttempts)
    }

    /// Generate a batch of mutually-unique codes (used by the pre-print flow).
    public func generateUniqueBatch(count: Int,
                                    maxAttemptsPerCode: Int = 100,
                                    isTaken: (String) -> Bool) throws -> [String] {
        var produced: [String] = []
        var seen = Set<String>()
        for _ in 0..<count {
            let code = try generateUnique(maxAttempts: maxAttemptsPerCode) { candidate in
                seen.contains(candidate) || isTaken(candidate)
            }
            seen.insert(code)
            produced.append(code)
        }
        return produced
    }

    // MARK: - Validation

    /// Structural validity: 18 chars, `IQ` prefix, body within the alphabet.
    public static func isValid(_ code: String) -> Bool {
        guard code.count == totalLength else { return false }
        guard code.hasPrefix(prefix) else { return false }
        let body = code.dropFirst(prefix.count)
        guard body.count == bodyLength else { return false }
        return body.allSatisfy { alphabetSet.contains($0) }
    }

    /// Looser check used by the scanner to decide if a foreign QR "looks like"
    /// one of ours before a DB lookup.
    public static func looksLikeAppCode(_ code: String) -> Bool {
        code.count == totalLength && code.hasPrefix(prefix)
    }

    // MARK: - Base32 (Crockford) encoding

    /// Encodes `bytes` MSB-first into exactly `symbolCount` Base32 symbols.
    /// For 10 bytes (80 bits) and 16 symbols the bit stream divides evenly.
    static func encodeBase32(_ bytes: [UInt8], symbolCount: Int) -> String {
        var output = String()
        output.reserveCapacity(symbolCount)
        var buffer = 0
        var bitsInBuffer = 0
        var emitted = 0

        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 && emitted < symbolCount {
                bitsInBuffer -= 5
                let index = (buffer >> bitsInBuffer) & 0x1F
                output.append(alphabet[index])
                emitted += 1
            }
        }
        // If callers ever request more symbols than the bytes provide, pad with
        // the leftover low bits shifted up. Not hit for the 10-byte/16-symbol
        // configuration, but keeps the function total.
        while emitted < symbolCount {
            let index = (buffer << (5 - bitsInBuffer)) & 0x1F
            output.append(alphabet[index])
            emitted += 1
            bitsInBuffer = 0
            buffer = 0
        }
        return output
    }
}
