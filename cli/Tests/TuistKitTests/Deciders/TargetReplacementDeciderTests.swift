import Testing
import XcodeGraph
@testable import TuistKit

struct TargetReplacementDeciderTests {
    @Test func externalOnly_replaces_external_only() {
        let decider = ExternalOnlyTargetReplacementDecider()
        #expect(decider.shouldReplace(
            project: Project.test(type: .external()),
            target: Target.test()
        ))
        #expect(!decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test()
        ))
    }

    @Test func allPossible_no_exceptions_replaces_everything() {
        let decider = AllPossibleTargetReplacementDecider(exceptions: [])
        #expect(decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test()
        ))
        #expect(decider.shouldReplace(
            project: Project.test(type: .external()),
            target: Target.test()
        ))
    }

    @Test func allPossible_with_name_exception_does_not_replace_that_name() {
        let decider = AllPossibleTargetReplacementDecider(exceptions: [.named("DoNotReplace")])
        #expect(!decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test(name: "DoNotReplace")
        ))
        #expect(decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test()
        ))
    }

    @Test func allPossible_with_tag_exception_does_not_replace_matching_tag() {
        let decider = AllPossibleTargetReplacementDecider(exceptions: [.tagged("DoNotReplace")])
        #expect(!decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test(metadata: .test(tags: ["DoNotReplace"]))
        ))
        #expect(decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test(metadata: .test(tags: ["Other"]))
        ))
        #expect(decider.shouldReplace(
            project: Project.test(type: .local),
            target: Target.test()
        ))
    }
}
