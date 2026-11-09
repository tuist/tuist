import Foundation
import TestCoverageAttribution
import Testing

@testable import TuistServer

@Suite(.coverageAttribution)
struct CacheStorableItemTests {
    @Test
    func cacheStorableItemsIsProperlyDeduplicatedInASet() {
        // When
        let got = Set(
            [
                CacheStorableItem(
                    name: "name_one",
                    hash: "hash_one"
                ),
                CacheStorableItem(
                    name: "name_one",
                    hash: "hash_one"
                ),
                CacheStorableItem(
                    name: "name_two",
                    hash: "hash_one"
                ),
            ]
        )

        // Then
        #expect(
            got.map(\.name).sorted() == [
                "name_one",
                "name_two",
            ]
        )
    }
}
