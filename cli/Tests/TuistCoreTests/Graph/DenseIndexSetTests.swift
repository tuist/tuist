import Testing

@testable import TuistCore

struct DenseIndexSetTests {
    @Test func insert_keepsIndicesOnBothSidesOfWordBoundaries() {
        var set = DenseIndexSet()
        for index in [200, 64, 0, 63, 127, 64] {
            set.insert(index)
        }

        #expect(Array(set) == [0, 63, 64, 127, 200])
        #expect(set.contains(63))
        #expect(set.contains(64))
        #expect(!set.contains(1))
        #expect(!set.contains(65))
        #expect(!set.contains(10000))
    }

    @Test func remove_dropsOnlyThatIndex() {
        var set = DenseIndexSet()
        [3, 64, 130].forEach { set.insert($0) }

        set.remove(64)
        set.remove(5000)

        #expect(Array(set) == [3, 130])

        set.remove(3)
        set.remove(130)

        #expect(set.isEmpty)
        #expect(Array(set).isEmpty)
    }

    @Test func formUnion_mergesSetsOfDifferentLengths() {
        var short = DenseIndexSet()
        [1, 62].forEach { short.insert($0) }
        var long = DenseIndexSet()
        [62, 65, 191].forEach { long.insert($0) }

        var shortThenLong = short
        shortThenLong.formUnion(long)
        var longThenShort = long
        longThenShort.formUnion(short)
        var empty = DenseIndexSet()
        empty.formUnion(long)

        #expect(Array(shortThenLong) == [1, 62, 65, 191])
        #expect(Array(longThenShort) == [1, 62, 65, 191])
        #expect(Array(empty) == [62, 65, 191])
        #expect(Array(long) == [62, 65, 191])
    }
}
