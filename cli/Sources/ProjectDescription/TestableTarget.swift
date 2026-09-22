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
    public var selectedTests: [String]
    public var skippedTests: [String]

    init(
        target: TargetReference,
        isSkipped: Bool,
        parallelization: Parallelization,
        isRandomExecutionOrdering: Bool,
        simulatedLocation: SimulatedLocation? = nil,
        selectedTests: [String] = [],
        skippedTests: [String] = []
    ) {
        self.target = target
        self.isSkipped = isSkipped
        self.parallelization = parallelization
        self.isRandomExecutionOrdering = isRandomExecutionOrdering
        self.simulatedLocation = simulatedLocation
        self.selectedTests = selectedTests
        self.skippedTests = skippedTests
    }

    /// Returns a testable target.
    ///
    /// - Parameters:
    ///   - target: The name or reference of target to test.
    ///   - isSkipped: Whether to skip this test target. If true, the test target is disabled.
    ///   - isParallelizable: Whether to run in parallel.
    ///   - isRandomExecutionOrdering: Whether to test in random order.
    ///   - simulatedLocation: The simulated GPS location to use when testing this target.
    ///   - selectedTests: Test identifiers to run for this target in a generated test plan.
    ///   - skippedTests: Test identifiers to skip for this target in a generated test plan.
    ///   Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.
    @available(
        *,
        deprecated,
        renamed: "testableTarget(target:isSkipped:parallelization:isRandomExecutionOrdering:simulatedLocation:selectedTests:skippedTests:)"
    )
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        isParallelizable: Bool,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil,
        selectedTests: [String] = [],
        skippedTests: [String] = []
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            parallelization: isParallelizable ? .enabled : .disabled,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation,
            selectedTests: selectedTests,
            skippedTests: skippedTests
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
    ///   - selectedTests: Test identifiers to run for this target in a generated test plan.
    ///   - skippedTests: Test identifiers to skip for this target in a generated test plan.
    ///   Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.
    public static func testableTarget(
        target: TargetReference,
        isSkipped: Bool = false,
        parallelization: Parallelization = .disabled,
        isRandomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil,
        selectedTests: [String] = [],
        skippedTests: [String] = []
    ) -> Self {
        self.init(
            target: target,
            isSkipped: isSkipped,
            parallelization: parallelization,
            isRandomExecutionOrdering: isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation,
            selectedTests: selectedTests,
            skippedTests: skippedTests
        )
    }

    public init(stringLiteral value: String) {
        self.init(
            target: TargetReference(projectPath: nil, target: value),
            isSkipped: false,
            parallelization: .disabled,
            isRandomExecutionOrdering: false,
            simulatedLocation: nil,
            selectedTests: [],
            skippedTests: []
        )
    }
}
