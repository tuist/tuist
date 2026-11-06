/// A set of small non-negative integers stored as a bit set.
///
/// Graph walks that memoize what is reachable below every node number the nodes once and keep one of these per node:
/// merging a child's set into its parent's is a word-wise OR instead of hashing every element again, and each set takes
/// one bit per node instead of a copy of every reachable value.
public struct DenseIndexSet: Sequence, Sendable {
    private var words: [UInt64] = []

    public init() {}

    public var isEmpty: Bool {
        words.allSatisfy { $0 == 0 }
    }

    public func contains(_ index: Int) -> Bool {
        let wordIndex = index >> 6
        return wordIndex < words.count && words[wordIndex] & (1 << UInt64(index & 63)) != 0
    }

    public mutating func insert(_ index: Int) {
        let wordIndex = index >> 6
        if wordIndex >= words.count {
            words.append(contentsOf: repeatElement(0, count: wordIndex - words.count + 1))
        }
        words[wordIndex] |= 1 << UInt64(index & 63)
    }

    public mutating func remove(_ index: Int) {
        let wordIndex = index >> 6
        guard wordIndex < words.count else { return }
        words[wordIndex] &= ~(1 << UInt64(index & 63))
    }

    public mutating func formUnion(_ other: DenseIndexSet) {
        if words.isEmpty {
            words = other.words
            return
        }
        if other.words.count > words.count {
            words.append(contentsOf: repeatElement(0, count: other.words.count - words.count))
        }
        for wordIndex in other.words.indices {
            words[wordIndex] |= other.words[wordIndex]
        }
    }

    /// The indices in ascending order.
    public func makeIterator() -> AnyIterator<Int> {
        var wordIndex = 0
        var word = words.first ?? 0
        return AnyIterator {
            while word == 0 {
                wordIndex += 1
                guard wordIndex < words.count else { return nil }
                word = words[wordIndex]
            }
            let bit = word.trailingZeroBitCount
            word &= word - 1
            return (wordIndex << 6) + bit
        }
    }
}
