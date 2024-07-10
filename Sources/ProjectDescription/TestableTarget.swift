import Foundation

public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation, Sendable {
    public var target: TargetReference
    public var isSkipped: Bool
    public var isParallelizable: Bool
    public var isRandomExecutionOrdering: Bool
    public var simulatedLocation: SimulatedLocation?

    init(
        target: TargetReference,
        isSkipped: Bool,
        isParallelizable: Bool,
        isRandomExecutionOrdering: Bool,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.target = target
        self.isSkipped = isSkipped
        self.isParallelizable = isParallelizable
        self.isRandomExecutionOrdering = isRandomExecutionOrdering
        self.simulatedLocation = simulatedLocation
    }

    /// Returns a testable target.
    ///
    /// - Parameters:
    ///   - target: The name or reference of target to test.
    ///   - isSkipped: Whether to skip this test target. If true, the test target is disabled.
    ///   - isParallelizable: Whether to run in parallel.
    ///   - isRandomExecutionOrdering: Whether to test in random order.
    ///   - simulatedLocation: The simulated GPS location to use when testing this target.
    ///   Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        isParallelizable: Bool = false,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            isParallelizable: isParallelizable,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }

    public init(stringLiteral value: String) {
        self.init(
            target: TargetReference(projectPath: nil, target: value),
            isSkipped: false,
            isParallelizable: false,
            isRandomExecutionOrdering: false,
            simulatedLocation: nil
        )
    }
}
