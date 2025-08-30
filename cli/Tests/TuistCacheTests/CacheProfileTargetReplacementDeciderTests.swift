import Testing
import TuistCore
import XcodeGraph
@testable import TuistKit

struct CacheProfileTargetReplacementDeciderTests {
    @Test func allPossible_without_exceptions_replaces_everything() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .allPossible,
            targets: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test()))
    }

    @Test func allPossible_with_name_exception_does_not_replace_that_name() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .allPossible,
            targets: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["DoNotReplace"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "DoNotReplace")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
    }

    @Test func allPossible_with_tag_exception_does_not_replace_matching_tag() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .allPossible,
            targets: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:DoNotReplace"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["DoNotReplace"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["Other"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
    }

    @Test func onlyExternal_replaces_external_and_specific_internals() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .onlyExternal,
            targets: ["A", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(name: "X")))

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "B")))

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["other"]))))
    }

    @Test func none_replaces_only_specific_internal_targets() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .none,
            targets: ["A", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test()))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }

    @Test func onlyExternal_with_no_targets_does_not_replace_internals() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .onlyExternal,
            targets: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test()))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "Any")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["any"]))))
    }

    @Test func onlyExternal_allowed_by_name_but_excepted_by_name_not_replaced() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .onlyExternal,
            targets: ["A"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["A"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
    }

    @Test func onlyExternal_allowed_by_tag_but_excepted_by_tag_not_replaced() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .onlyExternal,
            targets: ["tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:cacheable"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }

    @Test func onlyExternal_externals_ignored_by_exceptions_still_replaced() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .onlyExternal,
            targets: ["A", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["A", "tag:cacheable"])

        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(name: "A")))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test()))
    }

    @Test func none_allowed_by_name_but_excepted_by_name_not_replaced() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .none,
            targets: ["A"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["A"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
    }

    @Test func none_allowed_by_tag_but_excepted_by_tag_not_replaced() {
        let profile = TuistGeneratedProjectOptions.CacheProfile(
            base: .none,
            targets: ["tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:cacheable"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }
}
