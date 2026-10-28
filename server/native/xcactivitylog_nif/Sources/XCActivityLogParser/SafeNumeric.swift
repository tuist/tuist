import Foundation

enum SafeNumeric {
    /// XCLogParser reports `UInt64.max` for a diagnostic whose text-document
    /// location carries no line or column, and `0` when there is no location
    /// object at all. Both map to `0` here.
    static func location(_ number: UInt64) -> Int {
        number == UInt64.max ? 0 : Int(clamping: number)
    }

    static func milliseconds(_ seconds: Double, rounding rule: FloatingPointRoundingRule = .up) -> Int {
        let millis = (seconds * 1000).rounded(rule)
        guard millis.isFinite else { return 0 }
        if millis >= Double(Int.max) { return Int.max }
        if millis <= Double(Int.min) { return Int.min }
        return Int(millis)
    }
}
