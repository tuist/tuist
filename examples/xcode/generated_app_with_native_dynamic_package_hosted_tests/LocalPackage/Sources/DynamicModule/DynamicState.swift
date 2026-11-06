public final class DynamicState {
    public static let shared = DynamicState()
    public var value = 42

    private init() {}
}
