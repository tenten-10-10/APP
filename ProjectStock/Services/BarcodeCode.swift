import Foundation

/// Retail / logistics barcode recognition for ハンディモード: JAN (EAN-13 /
/// EAN-8), UPC-A and ITF-14. A barcode maps to a Product through a plain
/// `CodeAlias` whose `publicCode` stores the digits verbatim — no Core Data
/// schema change, and no collision with app QR codes, which are always 18
/// chars starting with "IQ" (PublicCodeGenerator) and never all-digits.
enum BarcodeCode {

    /// Digit lengths we accept: EAN-8(8) / UPC-A(12) / EAN-13(13) / ITF-14(14).
    static let acceptedLengths: Set<Int> = [8, 12, 13, 14]

    /// Returns the normalized digit string when `raw` is a valid barcode
    /// (accepted length + GS1 mod-10 check digit), else nil. Non-barcodes —
    /// including every app QR code — fall through to the normal QR routing.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard acceptedLengths.contains(trimmed.count) else { return nil }
        guard hasValidCheckDigit(trimmed) else { return nil }
        return trimmed
    }

    /// GS1 mod-10: weight digits ×3/×1 alternating from the RIGHTMOST digit of
    /// the body (everything except the final check digit).
    static func hasValidCheckDigit(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count == digits.count, nums.count >= 2, let check = nums.last else { return false }
        var sum = 0
        for (index, digit) in nums.dropLast().reversed().enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - (sum % 10)) % 10 == check
    }

    /// Human label for the symbology, keyed by length.
    static func typeName(for digits: String) -> String {
        switch digits.count {
        case 8:  return NSLocalizedString("JAN（短縮）", comment: "barcode type")
        case 12: return NSLocalizedString("UPC", comment: "barcode type")
        case 13: return NSLocalizedString("JAN", comment: "barcode type")
        case 14: return NSLocalizedString("ITF", comment: "barcode type")
        default: return NSLocalizedString("バーコード", comment: "barcode type")
        }
    }
}
