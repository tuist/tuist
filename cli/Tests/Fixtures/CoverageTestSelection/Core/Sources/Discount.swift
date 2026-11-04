public enum Discount {
    public static func apply(percent: Int, to price: Money) -> Money {
        Money(cents: price.cents * (100 - percent) / 100)
    }
}
