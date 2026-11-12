import Core

enum Prices {
    static func cents(_ value: Int) -> Money {
        Money(cents: value)
    }

    static func tenDollars() -> Money {
        cents(1000)
    }
}
