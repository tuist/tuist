import Foundation

/// Testable target describe target and tests information.
public struct TestableTarget: Equatable, Hashable, Codable {
    /// The target name and its project path.
    public let target: TargetReference
    /// Skip test target from TestAction.
    public let isSkipped: Bool
    /// Execute tests in parallel.
    public let isParallelizable: Bool
    /// Execute tests in random order.
    public let isRandomExecutionOrdering: Bool
    /// A simulated location used when testing this test target.
    public let simulatedLocation: SimulatedLocation?

    public init(
        target: TargetReference,
        skipped: Bool = false,
        parallelizable: Bool = false,
        randomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.target = target
        isSkipped = skipped
        isParallelizable = parallelizable
        isRandomExecutionOrdering = randomExecutionOrdering
        self.simulatedLocation = simulatedLocation
    }
}
