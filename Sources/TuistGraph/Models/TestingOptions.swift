public struct TestingOptions: OptionSet, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let parallelizable = TestingOptions(rawValue: 1 << 0)
    public static let randomExecutionOrdering = TestingOptions(rawValue: 1 << 1)
}
