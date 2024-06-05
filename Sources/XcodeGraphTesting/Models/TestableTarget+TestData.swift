import TSCBasic
import TuistSupport
import XcodeGraph

extension TestableTarget {
    public static func test(
        target: TargetReference = TargetReference(projectPath: "/Project", name: "App"),
        skipped: Bool = false,
        parallelizable: Bool = false,
        randomExecutionOrdering: Bool = false,
        simulatedLocation: SimulatedLocation? = nil
    ) -> TestableTarget {
        TestableTarget(
            target: target,
            skipped: skipped,
            parallelizable: parallelizable,
            randomExecutionOrdering: randomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }
}
