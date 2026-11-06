import Catalog
import Testing

@Suite struct SearchTests {
    @Test func matchesName() {
        #expect(ProductSearch.matches(name: "Coffee", query: "Cof"))
    }

    @Test func matchingIgnoresCase() {
        #expect(ProductSearch.matches(name: "Coffee", query: "coffee"))
    }
}
