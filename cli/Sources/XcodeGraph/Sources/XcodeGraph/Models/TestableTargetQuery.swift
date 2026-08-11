import Foundation

/// A query that matches the targets to test, along with the options every matched target is tested with.
public struct TestableTargetQuery: Equatable, Hashable, Codable, Sendable {
    /// The query the targets to test are matched against.
    public let query: TargetQuery
    /// Skip the matched test targets from the test action.
    public let isSkipped: Bool
    /// Execute the tests of the matched targets in parallel.
    public let parallelization: TestableTarget.Parallelization
    /// Execute the tests of the matched targets in random order.
    public let isRandomExecutionOrdering: Bool
    /// A simulated location used when testing the matched targets.
    public let simulatedLocation: SimulatedLocation?

    public init(
        query: TargetQuery,
        skipped: Bool = false,
        parallelization: TestableTarget.Parallelization = .none,
        randomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.query = query
        isSkipped = skipped
        self.parallelization = parallelization
        isRandomExecutionOrdering = randomExecutionOrdering
        self.simulatedLocation = simulatedLocation
    }

    /// Returns a testable target for a target matched by the query, carrying over the options of the query.
    public func testableTarget(for target: TargetReference) -> TestableTarget {
        TestableTarget(
            target: target,
            skipped: isSkipped,
            parallelization: parallelization,
            randomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }

    #if DEBUG
        public static func test(
            query: TargetQuery = .matching(pattern: "*Tests"),
            skipped: Bool = false,
            parallelization: TestableTarget.Parallelization = .none,
            randomExecutionOrdering: Bool = false,
            simulatedLocation: SimulatedLocation? = nil
        ) -> TestableTargetQuery {
            TestableTargetQuery(
                query: query,
                skipped: skipped,
                parallelization: parallelization,
                randomExecutionOrdering: randomExecutionOrdering,
                simulatedLocation: simulatedLocation
            )
        }
    #endif
}
