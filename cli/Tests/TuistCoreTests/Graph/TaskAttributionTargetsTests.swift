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
            Target.test(
                name: "TestCoverageAttribution",
                product: .staticFramework,
                sources: [SourceFile(path: path.appending(components: "TestCoverageAttribution", "SanitizerCoverage.swift"))]
            ),
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

    @Test func leavesOutTheTargetsOfExternalPackages() throws {
        let path = try AbsolutePath(validating: "/Project")
        let packagePath = try AbsolutePath(validating: "/Project/.build/checkouts/NIO")
        let tests = Target.test(
            name: "CoreTests",
            product: .unitTests,
            sources: [SourceFile(path: path.appending(component: "CoreTests.swift"))]
        )
        let attribution = Target.test(
            name: "TestCoverageAttribution",
            product: .staticFramework,
            sources: [SourceFile(path: path.appending(components: "TestCoverageAttribution", "SanitizerCoverage.swift"))]
        )
        let nio = Target.test(
            name: "NIO",
            product: .staticFramework,
            sources: [SourceFile(path: packagePath.appending(component: "NIO.swift"))]
        )
        let graph = Graph.test(
            projects: [
                path: Project.test(path: path, targets: [tests, attribution]),
                packagePath: Project.test(path: packagePath, targets: [nio], type: .external(hash: nil)),
            ],
            dependencies: [
                .target(name: "CoreTests", path: path): [
                    .target(name: "TestCoverageAttribution", path: path), .target(name: "NIO", path: packagePath),
                ],
            ]
        )

        #expect(TaskAttributionTargets.identifiers(graph: graph) == ["CoreTests"])
    }

    /// A package that predates the callbacks would leave tracked code with nothing to link against.
    @Test func picksNothingWhenThePackageDoesNotDefineTheCallbacks() throws {
        let path = try AbsolutePath(validating: "/Project")
        let tests = Target.test(
            name: "CoreTests",
            product: .unitTests,
            sources: [SourceFile(path: path.appending(component: "CoreTests.swift"))]
        )
        let attribution = Target.test(
            name: "TestCoverageAttribution",
            product: .staticFramework,
            sources: [SourceFile(path: path.appending(components: "TestCoverageAttribution", "CoverageAttributionTrait.swift"))]
        )
        let graph = Graph.test(
            projects: [path: Project.test(path: path, targets: [tests, attribution])],
            dependencies: [.target(name: "CoreTests", path: path): [.target(name: "TestCoverageAttribution", path: path)]]
        )

        #expect(TaskAttributionTargets.identifiers(graph: graph).isEmpty)
    }

    @Test func writesNamesAsC99ExtendedIdentifiers() {
        #expect(TaskAttributionTargets.identifier("Core-iOS Tests") == "Core_iOS_Tests")
        #expect(TaskAttributionTargets.identifier("2D") == "_2D")
    }
}
