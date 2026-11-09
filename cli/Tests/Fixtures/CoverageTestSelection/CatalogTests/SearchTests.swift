import Catalog
import TestCoverageAttribution
import Testing

// Serialized: the baseline runs with parallel testing, and tests that overlap in one process record
// no evidence of their own.
@Suite(.coverageAttribution, .serialized) struct SearchTests {
    @Test func matchesName() {
        #expect(ProductSearch.matches(name: "Coffee", query: "Cof"))
    }

    @Test func matchingIgnoresCase() {
        #expect(ProductSearch.matches(name: "Coffee", query: "coffee"))
    }
}
