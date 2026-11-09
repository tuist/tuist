import Foundation
import Testing
import TuistCore
@testable import TuistKit

struct ShardTestSelectionTests {
    @Test func plan_withoutRequestedIdentifiers_leavesTheUniverseUntouched() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppTests", "AppUITests"],
            parallelizableModules: ["AppTests"],
            selectedTestSuites: ["AppUITests/OnboardingFlowTests"],
            skippedTestSuites: ["AppUITests/CheckoutFlowTests"],
            requested: []
        )

        #expect(
            selection == ShardTestSelection.Plan(
                modules: ["AppTests", "AppUITests"],
                parallelizableModules: ["AppTests"],
                selectedTestSuites: ["AppUITests/OnboardingFlowTests"],
                skippedTestSuites: ["AppUITests/CheckoutFlowTests"]
            )
        )
    }

    @Test func plan_withRequestedSuites_restrictsAnOtherwiseUnrestrictedModule() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppUITests"],
            parallelizableModules: ["AppUITests"],
            selectedTestSuites: [],
            skippedTestSuites: [],
            requested: [
                try TestIdentifier(target: "AppUITests", class: "CartA11yTests"),
                try TestIdentifier(target: "AppUITests", class: "CheckoutA11yTests"),
            ]
        )

        #expect(selection.modules == ["AppUITests"])
        #expect(
            selection.selectedTestSuites == [
                "AppUITests/CartA11yTests",
                "AppUITests/CheckoutA11yTests",
            ]
        )
    }

    @Test func plan_withRequestedMethod_restrictsToTheSuiteHoldingIt() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppUITests"],
            parallelizableModules: [],
            selectedTestSuites: [],
            skippedTestSuites: [],
            requested: [
                try TestIdentifier(target: "AppUITests", class: "CartA11yTests", method: "testLabels()"),
            ]
        )

        #expect(selection.selectedTestSuites == ["AppUITests/CartA11yTests"])
    }

    @Test func plan_withRequestedTarget_leavesTheModuleUnrestricted() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppTests", "AppUITests"],
            parallelizableModules: ["AppTests", "AppUITests"],
            selectedTestSuites: [],
            skippedTestSuites: ["AppTests/BrokenSuite"],
            requested: [try TestIdentifier(target: "AppUITests")]
        )

        #expect(selection.modules == ["AppUITests"])
        #expect(selection.parallelizableModules == ["AppUITests"])
        #expect(selection.selectedTestSuites.isEmpty)
        #expect(selection.skippedTestSuites.isEmpty)
    }

    @Test func plan_withATargetAndOneOfItsSuites_leavesTheModuleUnrestricted() throws {
        // Both reach xcodebuild as `-only-testing`, which runs their union, so the whole module runs.
        let selection = ShardTestSelection.plan(
            modules: ["AppUITests"],
            parallelizableModules: [],
            selectedTestSuites: [],
            skippedTestSuites: [],
            requested: [
                try TestIdentifier(target: "AppUITests", class: "CartA11yTests"),
                try TestIdentifier(target: "AppUITests"),
            ]
        )

        #expect(selection.modules == ["AppUITests"])
        #expect(selection.selectedTestSuites.isEmpty)
    }

    @Test func plan_withProductsAlreadyRestricted_keepsOnlyWhatBothSidesAllow() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppUITests"],
            parallelizableModules: [],
            selectedTestSuites: ["AppUITests/CartA11yTests", "AppUITests/OnboardingFlowTests"],
            skippedTestSuites: [],
            requested: [
                try TestIdentifier(target: "AppUITests", class: "CartA11yTests"),
                try TestIdentifier(target: "AppUITests", class: "CheckoutA11yTests"),
            ]
        )

        #expect(selection.selectedTestSuites == ["AppUITests/CartA11yTests"])
    }

    @Test func plan_whenTheProductsAndTheRequestDisagreeEntirely_dropsTheModule() throws {
        let selection = ShardTestSelection.plan(
            modules: ["AppUITests"],
            parallelizableModules: ["AppUITests"],
            selectedTestSuites: ["AppUITests/OnboardingFlowTests"],
            skippedTestSuites: ["AppUITests/OnboardingFlowTests"],
            requested: [try TestIdentifier(target: "AppUITests", class: "CartA11yTests")]
        )

        #expect(selection.modules.isEmpty)
        #expect(selection.parallelizableModules.isEmpty)
        #expect(selection.selectedTestSuites.isEmpty)
        #expect(selection.skippedTestSuites.isEmpty)
    }

    @Test func onlyTestIdentifiers_withoutRestrictions_runsEverything() throws {
        #expect(ShardTestSelection.onlyTestIdentifiers([[], []]).isEmpty)
    }

    @Test func onlyTestIdentifiers_withASingleRestriction_keepsIt() throws {
        #expect(ShardTestSelection.onlyTestIdentifiers([["AppUITests"], []]) == ["AppUITests"])
    }

    @Test func onlyTestIdentifiers_onACatchAllShard_keepsTheRequestedOnes() throws {
        // A catch-all shard carries no identifiers of its own and relies on `-skip-testing`.
        #expect(
            ShardTestSelection.onlyTestIdentifiers([[], ["AppUITests/CartA11yTests"]])
                == ["AppUITests/CartA11yTests"]
        )
    }

    @Test func onlyTestIdentifiers_withAModuleGranularityShard_narrowsToTheRequestedSuites() throws {
        #expect(
            ShardTestSelection.onlyTestIdentifiers([
                ["AppUITests"],
                ["AppUITests/CartA11yTests", "AppUITests/CheckoutA11yTests"],
            ]) == ["AppUITests/CartA11yTests", "AppUITests/CheckoutA11yTests"]
        )
    }

    @Test func onlyTestIdentifiers_withASuiteGranularityShard_keepsTheShardsSuite() throws {
        #expect(
            ShardTestSelection.onlyTestIdentifiers([["AppUITests/CartA11yTests"], ["AppUITests"]])
                == ["AppUITests/CartA11yTests"]
        )
    }

    @Test func onlyTestIdentifiers_withASuiteNothingAskedFor_dropsIt() throws {
        #expect(
            ShardTestSelection.onlyTestIdentifiers([
                ["AppUITests/OnboardingFlowTests"],
                ["AppUITests/CartA11yTests"],
            ]).isEmpty
        )
    }

    @Test func onlyTestIdentifiers_withAnotherModulesShard_dropsIt() throws {
        #expect(
            ShardTestSelection.onlyTestIdentifiers([["AppTests"], ["AppUITests/CartA11yTests"]]).isEmpty
        )
    }

    @Test func onlyTestIdentifiers_narrowsThroughEveryRestrictionInTurn() throws {
        // Shard, then what the build job was asked for, then what this runner was asked for.
        #expect(
            ShardTestSelection.onlyTestIdentifiers([
                ["AppUITests"],
                ["AppUITests/CartA11yTests", "AppUITests/CheckoutA11yTests"],
                ["AppUITests/CartA11yTests"],
            ]) == ["AppUITests/CartA11yTests"]
        )
    }

    @Test func onlyTestIdentifiers_staysEmptyOnceARestrictionRulesEverythingOut() throws {
        // Nothing survives the first two, and the third must not resurrect the selection.
        #expect(
            ShardTestSelection.onlyTestIdentifiers([
                ["AppUITests/CartA11yTests"],
                ["AppUITests/CheckoutA11yTests"],
                ["AppUITests/CoreTests"],
            ]).isEmpty
        )
    }
}
