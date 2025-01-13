public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation, Sendable {
    /// With the introduction of Swift Testing and Xcode 16, you can now choose to run your tests
    /// in parallel across either the full suite of tests in a target with `.enabled`, just those created
    /// under Swift Testing with `.swiftTestingOnly`, or run them serially with the `.disabled` option.
    public enum Parallelization: Equatable, Codable, Sendable {
        case disabled, swiftTestingOnly, enabled
    }

    public var target: TargetReference
    public var isSkipped: Bool
    @available(
        *,
        deprecated,
        renamed: "parallelization",
        message: "isParallelizable is deprecated. Use the parallelization property instead."
    )
    public var isParallelizable: Bool {
        switch parallelization {
        case .disabled:
            false
        case .swiftTestingOnly:
            false
        case .enabled:
            true
        }
    }

    public var parallelization: Parallelization
    public var isRandomExecutionOrdering: Bool
    public var simulatedLocation: SimulatedLocation?

    init(
        target: TargetReference,
        isSkipped: Bool,
        parallelization: Parallelization,
        isRandomExecutionOrdering: Bool,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.target = target
        self.isSkipped = isSkipped
        self.parallelization = parallelization
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
    @available(
        *,
        deprecated,
        renamed: "testableTarget(target:isSkipped:parallelization:isRandomExecutionOrdering:simulatedLocation:)"
    )
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        isParallelizable: Bool,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            parallelization: isParallelizable ? .enabled : .disabled,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }

    /// Returns a testable target.
    ///
    /// - Parameters:
    ///   - target: The name or reference of target to test.
    ///   - isSkipped: Whether to skip this test target. If true, the test target is disabled.
    ///   - parallelization: Whether to run tests in parallel. Can be either `.disabled`, `.enabled`, or `.swiftTestingOnly`. The
    /// default value is `.disabled`.
    ///   - isRandomExecutionOrdering: Whether to test in random order.
    ///   - simulatedLocation: The simulated GPS location to use when testing this target.
    ///   Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        parallelization: Parallelization = .disabled,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            parallelization: parallelization,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }

    public init(stringLiteral value: String) {
        self.init(
            target: TargetReference(projectPath: nil, target: value),
            isSkipped: false,
            parallelization: .disabled,
            isRandomExecutionOrdering: false,
            simulatedLocation: nil
        )
    }
}
