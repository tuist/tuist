import Core
import Foundation

public struct Summary: Sendable {
    public let count: Int
    public let largest: String?

    public init(_ ledger: Ledger) {
        count = ledger.entries.count
        largest = ledger.entries.max { $0.value < $1.value }?.key
    }
}
