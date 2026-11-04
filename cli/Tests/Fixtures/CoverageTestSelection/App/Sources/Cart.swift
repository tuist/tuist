import Catalog
import Core
import SwiftUI

final class Cart: ObservableObject {
    @Published private(set) var items: [Product] = []
    @Published var discountPercent = 0

    func add(_ product: Product) {
        items.append(product)
    }

    var total: Money {
        let subtotal = items.reduce(Money(cents: 0)) { $0 + Money(cents: $1.priceCents) }
        if discountPercent > 0 {
            return Discount.apply(percent: discountPercent, to: subtotal)
        }
        return subtotal
    }
}
