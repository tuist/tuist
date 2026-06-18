public struct TestingOptions: Sendable, OptionSet, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let parallelizable = TestingOptions(rawValue: 1 << 0)
    public static let randomExecutionOrdering = TestingOptions(rawValue: 1 << 1)
    public static let swiftTestingOnlyParallelizable = TestingOptions(rawValue: 1 << 2)

    /// The parallelization mode resolved from the option set.
    ///
    /// `swiftTestingOnlyParallelizable` takes precedence over `parallelizable`: when both
    /// are set the result is `.swiftTestingOnly`, with only `parallelizable` it is `.all`,
    /// and with neither it is `.none`.
    public var parallelization: TestableTarget.Parallelization {
        if contains(.swiftTestingOnlyParallelizable) {
            .swiftTestingOnly
        } else if contains(.parallelizable) {
            .all
        } else {
            .none
        }
    }
}
