public final class StaticState {
    public static let shared = StaticState()
    public var value = 0

    private init() {}
}
