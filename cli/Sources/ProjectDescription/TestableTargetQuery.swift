/// A query that matches the targets to test, along with the options to test every matched target with.
///
/// Unlike ``TestableTarget``, which points at a single target, a query is resolved against every target of the
/// graph, so a single entry can cover targets that live in different projects:
///
/// ```swift
/// .scheme(
///     name: "AllUnitTests",
///     testAction: .targets(matching: ["*-UnitTests"])
/// )
/// ```
public struct TestableTargetQuery: Equatable, Codable, ExpressibleByStringLiteral, Sendable {
    /// The query the targets to test are matched against.
    public var query: TargetQuery

    /// Whether to skip the matched test targets. If true, they are disabled.
    public var isSkipped: Bool

    /// Whether to run the tests of the matched targets in parallel.
    public var parallelization: TestableTarget.Parallelization

    /// Whether to test the matched targets in random order.
    public var isRandomExecutionOrdering: Bool

    /// The simulated GPS location to use when testing the matched targets.
    public var simulatedLocation: SimulatedLocation?

    init(
        query: TargetQuery,
        isSkipped: Bool,
        parallelization: TestableTarget.Parallelization,
        isRandomExecutionOrdering: Bool,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.query = query
        self.isSkipped = isSkipped
        self.parallelization = parallelization
        self.isRandomExecutionOrdering = isRandomExecutionOrdering
        self.simulatedLocation = simulatedLocation
    }

    /// Returns a query matching the targets to test.
    ///
    /// - Parameters:
    ///   - query: The query the targets to test are matched against, for example `"*-UnitTests"` or `"tag:unit-tests"`.
    ///   - isSkipped: Whether to skip the matched test targets. If true, they are disabled.
    ///   - parallelization: Whether to run tests in parallel. Can be either `.disabled`, `.enabled`, or
    /// `.swiftTestingOnly`. The default value is `.disabled`.
    ///   - isRandomExecutionOrdering: Whether to test in random order.
    ///   - simulatedLocation: The simulated GPS location to use when testing the matched targets.
    ///   Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.
    public static func testableTargets(
        matching query: TargetQuery,
        isSkipped: Bool = false,
        parallelization: TestableTarget.Parallelization = .disabled,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) -> Self {
        self.init(
            query: query,
            isSkipped: isSkipped,
            parallelization: parallelization,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }

    public init(stringLiteral value: String) {
        self.init(
            query: TargetQuery(stringLiteral: value),
            isSkipped: false,
            parallelization: .disabled,
            isRandomExecutionOrdering: false,
            simulatedLocation: nil
        )
    }
}
