import Catalog
import Core

enum Receipt {
    static func lines(for items: [Product], discountPercent: Int) -> [String] {
        let subtotal = items.reduce(Money(cents: 0)) { $0 + Money(cents: $1.priceCents) }
        var lines = items.map { "\($0.name) \(Money(cents: $0.priceCents).formatted)" }
        if discountPercent > 0 {
            lines.append("\(discountPercent)% off: \(Discount.apply(percent: discountPercent, to: subtotal).formatted)")
        }
        return lines
    }
}
