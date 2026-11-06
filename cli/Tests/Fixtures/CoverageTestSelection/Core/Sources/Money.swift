public struct Money: Equatable, PriceDisplaying {
    public let cents: Cents

    public init(cents: Cents) {
        self.cents = cents
    }

    public var formatted: String {
        let dollars = cents / 100
        let remainder = cents % 100
        return "$\(dollars).\(remainder < 10 ? "0" : "")\(remainder)"
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }
}
