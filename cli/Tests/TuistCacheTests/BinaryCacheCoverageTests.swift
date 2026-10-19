import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistCache

struct BinaryCacheCoverageTests {
    @Test func offAndOnDoNotReadTheGraph() {
        let graph = Graph.test()

        #expect(BinaryCacheCoverage.off.isOn(in: graph) == false)
        #expect(BinaryCacheCoverage.on.isOn(in: graph) == true)
    }

    @Test func readsTheTestActionOfTheNamedScheme() throws {
        let plan = TestPlan(path: try AbsolutePath(validating: "/App.xctestplan"), testTargets: [], isDefault: true)
        let workspace = Workspace.test(
            name: "App",
            schemes: [
                .test(name: "Covered", testAction: .test(coverage: true)),
                .test(name: "Plain", testAction: .test(coverage: false)),
                .test(name: "Planned", testAction: .test(coverage: true, testPlans: [plan])),
                .test(name: "Untested", testAction: nil),
                .test(name: "App-Workspace", testAction: .test(coverage: true)),
            ]
        )
        let graph = Graph.test(workspace: workspace)

        #expect(BinaryCacheCoverage.scheme("Covered").isOn(in: graph) == true)
        #expect(BinaryCacheCoverage.scheme("Plain").isOn(in: graph) == false)
        #expect(BinaryCacheCoverage.scheme("Planned").isOn(in: graph) == false)
        #expect(BinaryCacheCoverage.scheme("Untested").isOn(in: graph) == false)
        #expect(BinaryCacheCoverage.scheme("Missing").isOn(in: graph) == false)
    }

    @Test func readsTheWorkspaceSchemeWhenNoSchemeIsNamed() {
        let covered = Workspace.test(name: "App", schemes: [.test(name: "App-Workspace", testAction: .test(coverage: true))])
        let plain = Workspace.test(name: "App", schemes: [.test(name: "App-Workspace", testAction: .test(coverage: false))])

        #expect(BinaryCacheCoverage.scheme(nil).isOn(in: Graph.test(workspace: covered)) == true)
        #expect(BinaryCacheCoverage.scheme(nil).isOn(in: Graph.test(workspace: plain)) == false)
    }
}
