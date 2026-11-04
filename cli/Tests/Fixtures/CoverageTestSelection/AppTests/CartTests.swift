import Catalog
import Core
import Testing
@testable import App

@Suite struct CartTests {
    @Test func totalSumsItems() {
        let cart = Cart()
        cart.add(Product(sku: "tea", name: "Tea", priceCents: 300))
        cart.add(Product(sku: "cake", name: "Cake", priceCents: 450))
        #expect(cart.total == Money(cents: 750))
    }

    @Test func discountAppliesToTotal() {
        let cart = Cart()
        cart.add(Product(sku: "cake", name: "Cake", priceCents: 450))
        cart.discountPercent = 10
        #expect(cart.total == Money(cents: 405))
    }
}
