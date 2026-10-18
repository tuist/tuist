import Foundation

public struct Ledger: Sendable {
    public private(set) var entries: [String: Int] = [:]

    public init() {}

    public mutating func record(_ name: String, amount: Int) {
        entries[name, default: 0] += amount
    }

    public var total: Int {
        entries.values.reduce(0, +)
    }

    public var checksum: Checksum {
        Checksum(entries.keys.sorted().joined(separator: ",").utf8)
    }
}
