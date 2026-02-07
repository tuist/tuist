import Testing
import TuistConfig
import TuistCore
import XcodeGraph
@testable import TuistCache

struct CacheProfileTargetReplacementDeciderTests {
    @Test func allPossible_without_exceptions_replaces_everything() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test()))
    }

    @Test func allPossible_with_name_exception_does_not_replace_that_name() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["DoNotReplace"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "DoNotReplace")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
    }

    @Test func allPossible_with_tag_exception_does_not_replace_matching_tag() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:DoNotReplace"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["DoNotReplace"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["Other"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
    }

    @Test func onlyExternal_replaces_external_and_specific_internals() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: ["A", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(name: "X")))

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "B")))

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["other"]))))
    }

    @Test func none_replaces_only_specific_internal_targets() {
        let profile = TuistConfig.CacheProfile(
            base: .none,
            targetQueries: ["A", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test()))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }

    @Test func onlyExternal_with_no_targets_does_not_replace_internals() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test()))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "Any")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["any"]))))
    }

    @Test func onlyExternal_allowed_by_name_but_excepted_by_name_not_replaced() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: ["A"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["A"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
    }

    @Test func onlyExternal_allowed_by_tag_but_excepted_by_tag_not_replaced() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: ["tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:cacheable"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }

    @Test func none_allowed_by_name_but_excepted_by_name_not_replaced() {
        let profile = TuistConfig.CacheProfile(
            base: .none,
            targetQueries: ["A"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["A"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
    }

    @Test func none_allowed_by_tag_but_excepted_by_tag_not_replaced() {
        let profile = TuistConfig.CacheProfile(
            base: .none,
            targetQueries: ["tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["tag:cacheable"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
    }

    @Test func onlyExternal_with_external_target_in_exceptions_should_not_replace() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(
            profile: profile,
            exceptions: ["ExternalDependency", "tag:keep-source"]
        )

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test(name: "ExternalDependency")))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(name: "OtherExternal")))

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test(metadata: .test(tags: ["keep-source"]))))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(metadata: .test(tags: ["other"]))))
    }

    @Test func allPossible_with_external_target_in_exceptions_should_not_replace() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: []
        )
        let decider = CacheProfileTargetReplacementDecider(
            profile: profile,
            exceptions: ["ExternalDependency", "tag:keep-source"]
        )

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test(name: "ExternalDependency")))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(name: "OtherExternal")))

        #expect(!decider.shouldReplace(project: .test(type: .external()), target: .test(metadata: .test(tags: ["keep-source"]))))
        #expect(decider.shouldReplace(project: .test(type: .external()), target: .test(metadata: .test(tags: ["other"]))))
    }

    @Test func allPossible_with_profile_exceptTargetQueries_does_not_replace() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: [],
            exceptTargetQueries: ["DoNotReplace", "tag:DoNotReplaceTag"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "DoNotReplace")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["DoNotReplaceTag"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["Other"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test()))
    }

    @Test func onlyExternal_with_profile_exceptTargetQueries_excludes_from_replacement() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: ["A", "tag:cacheable"],
            exceptTargetQueries: ["B", "tag:exclude"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "B")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["exclude"]))))
    }

    @Test func exceptTargetQueries_overrides_targetQueries() {
        let profile = TuistConfig.CacheProfile(
            base: .onlyExternal,
            targetQueries: ["A", "B", "tag:cacheable", "tag:shared"],
            exceptTargetQueries: ["B", "tag:cacheable"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: [])

        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "A")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "B")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["shared"]))))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["cacheable"]))))
        #expect(!decider.shouldReplace(
            project: .test(type: .local),
            target: .test(metadata: .test(tags: ["shared", "cacheable"]))
        ))
    }

    @Test func profile_exceptTargetQueries_combines_with_focus_exceptions() {
        let profile = TuistConfig.CacheProfile(
            base: .allPossible,
            targetQueries: [],
            exceptTargetQueries: ["ProfileExcluded", "tag:profileExclude"]
        )
        let decider = CacheProfileTargetReplacementDecider(profile: profile, exceptions: ["FocusExcluded", "tag:focusExclude"])

        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "ProfileExcluded")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(name: "FocusExcluded")))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(name: "Other")))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["profileExclude"]))))
        #expect(!decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["focusExclude"]))))
        #expect(decider.shouldReplace(project: .test(type: .local), target: .test(metadata: .test(tags: ["other"]))))
    }
}
