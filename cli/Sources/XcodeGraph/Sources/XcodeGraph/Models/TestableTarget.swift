import Foundation
import Path

/// Testable target describe target and tests information.
public struct TestableTarget: Equatable, Hashable, Codable, Sendable {
    /// With the introduction of Swift Testing and Xcode 16, you can now choose to run your tests
    /// in parallel across either the full suite of tests in a target with `.all`, just those created
    /// under Swift Testing with `.swiftTestingOnly`, or run them serially with the `.none` option.
    public enum Parallelization: Equatable, Hashable, Codable, Sendable {
        case none, swiftTestingOnly, all
    }

    /// The target name and its project path.
    public let target: TargetReference
    /// Skip test target from TestAction.
    public let isSkipped: Bool

    /// Execute tests in parallel.
    @available(
        *,
        deprecated,
        renamed: "parallelization",
        message: "isParallelizable was deprecated. Use the paralellization property instead."
    )
    public var isParallelizable: Bool {
        parallelization == .none
    }

    public let parallelization: Parallelization

    /// Execute tests in random order.
    public let isRandomExecutionOrdering: Bool
    /// A simulated location used when testing this test target.
    public let simulatedLocation: SimulatedLocation?

    /// Swift Testing tag names, in the dotted spelling Xcode writes (e.g. `".contract"`), whose tests
    /// are the only ones the target runs. Written as `selectedTags` into generated `.xctestplan` files
    /// and ignored by scheme test actions.
    public let selectedTags: [String]

    /// Swift Testing tag names, in the dotted spelling Xcode writes (e.g. `".contract"`), whose tests
    /// the target skips. Written as `skippedTags` into generated `.xctestplan` files and ignored by
    /// scheme test actions.
    public let skippedTags: [String]

    @available(*, deprecated, renamed: "init(target:skipped:parallelization:randomExecutionOrdering:simulatedLocation:)")
    public init(
        target: TargetReference,
        skipped: Bool = false,
        parallelizable: Bool,
        randomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.target = target
        isSkipped = skipped
        parallelization = parallelizable ? .all : .none
        isRandomExecutionOrdering = randomExecutionOrdering
        self.simulatedLocation = simulatedLocation
        selectedTags = []
        skippedTags = []
    }

    public init(
        target: TargetReference,
        skipped: Bool = false,
        parallelization: Parallelization = .none,
        randomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil,
        selectedTags: [String] = [],
        skippedTags: [String] = []
    ) {
        self.target = target
        isSkipped = skipped
        self.parallelization = parallelization
        isRandomExecutionOrdering = randomExecutionOrdering
        self.simulatedLocation = simulatedLocation
        self.selectedTags = selectedTags
        self.skippedTags = skippedTags
    }

    #if DEBUG
        public static func test(
            // swiftlint:disable:next force_try
            target: TargetReference = TargetReference(projectPath: try! AbsolutePath(validating: "/Project"), name: "App"),
            skipped: Bool = false,
            parallelizable: Bool = false,
            randomExecutionOrdering: Bool = false,
            simulatedLocation: SimulatedLocation? = nil,
            selectedTags: [String] = [],
            skippedTags: [String] = []
        ) -> TestableTarget {
            TestableTarget(
                target: target,
                skipped: skipped,
                parallelization: parallelizable ? .all : .none,
                randomExecutionOrdering: randomExecutionOrdering,
                simulatedLocation: simulatedLocation,
                selectedTags: selectedTags,
                skippedTags: skippedTags
            )
        }
    #endif
}
