import Path
import Testing
import XcodeGraph
@testable import TuistCore

struct TaskAttributionTargetsTests {
    @Test func picksTheTestTargetsThatLinkThePackageAndTheStaticTargetsOnlyTheyLink() throws {
        // CoreTests ---> Core ---> Shared <--- App
        //    \---> TestCoverageAttribution
        // PlainTests ---> Plain
        let path = try AbsolutePath(validating: "/Project")
        func target(_ name: String, _ product: Product, swift: Bool = true) throws -> Target {
            Target.test(
                name: name,
                product: product,
                sources: swift ? [SourceFile(path: path.appending(component: "\(name).swift"))] : []
            )
        }
        let targets = try [
            target("Core", .staticFramework),
            target("Shared", .staticFramework),
            target("CoreTests", .unitTests),
            target("App", .app),
            target("Plain", .staticFramework),
            target("PlainTests", .unitTests),
            target("TestCoverageAttribution", .staticFramework),
            target("Resources-Only", .staticLibrary, swift: false),
        ]
        let project = Project.test(path: path, targets: targets)
        func dependency(_ name: String) -> GraphDependency {
            .target(name: name, path: path)
        }
        let graph = Graph.test(
            projects: [path: project],
            dependencies: [
                dependency("CoreTests"): [
                    dependency("Core"),
                    dependency("TestCoverageAttribution"),
                    dependency("Resources-Only"),
                ],
                dependency("Core"): [dependency("Shared")],
                dependency("App"): [dependency("Shared")],
                dependency("PlainTests"): [dependency("Plain")],
            ]
        )

        #expect(TaskAttributionTargets.identifiers(graph: graph) == ["Core", "CoreTests"])
    }

    @Test func writesNamesAsC99ExtendedIdentifiers() {
        #expect(TaskAttributionTargets.identifier("Core-iOS Tests") == "Core_iOS_Tests")
        #expect(TaskAttributionTargets.identifier("2D") == "_2D")
    }
}
