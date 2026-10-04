import Path
import Testing

@testable import ProjectDescription

struct BuildActionTests {
    @Test func buildAction_withPerTargetBuildForOptions() {
        let subject = BuildAction.buildAction(
            buildActionTargets: [
                .target("App", buildFor: [.analyzing, .archiving, .profiling, .running]),
                .target("AppTests", buildFor: [.testing]),
            ]
        )

        #expect(subject.targets == [.target("App"), .target("AppTests")])
        #expect(subject.buildFor[.target("App")] == [.analyzing, .archiving, .profiling, .running])
        #expect(subject.buildFor[.target("AppTests")] == [.testing])
    }

    @Test func targetDefaultsToAllBuildForOptions() {
        let subject = BuildActionTarget.target("App")

        #expect(subject.target == .target("App"))
        #expect(subject.buildFor == Set(BuildActionTarget.BuildFor.allCases))
    }

    @Test func projectTargetDefaultsToAllBuildForOptions() {
        let projectPath = Path.relativeToManifest("../Feature")
        let subject = BuildActionTarget.project(path: projectPath, target: "Feature")

        #expect(subject.target == .project(path: projectPath, target: "Feature"))
        #expect(subject.buildFor == Set(BuildActionTarget.BuildFor.allCases))
    }

    @Test func existingBuildActionAPIUsesDefaultBuildForBehavior() {
        let subject = BuildAction.buildAction(targets: [.target("App")])

        #expect(subject.targets == [.target("App")])
        #expect(subject.buildFor.isEmpty)
    }
}
