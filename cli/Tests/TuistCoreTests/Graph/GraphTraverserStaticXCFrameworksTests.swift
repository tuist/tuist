import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore

struct GraphTraverserStaticXCFrameworksTests {
    @Test(.inTemporaryDirectory)
    func staticXCFrameworksLinkedByDynamicXCFrameworkDependencies_whenDynamicXCFrameworksOverlapAndChain() throws {
        // App ---> DynamicA ---> StaticSwiftA
        //      |           \--> DynamicB ---> StaticSwiftB
        //      \--> DynamicB
        //
        // `DynamicB` is both a direct dependency and reachable through `DynamicA`, which is what makes the
        // per-root walk observable: the statics behind it must be reported exactly once and from either path.

        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])
        let staticSwiftAPath = temporaryDirectory.appending(component: "StaticSwiftA.xcframework")
        let staticSwiftBPath = temporaryDirectory.appending(component: "StaticSwiftB.xcframework")

        let dynamicA = GraphDependency.testXCFramework(path: "/test/DynamicA.xcframework", linking: .dynamic)
        let dynamicB = GraphDependency.testXCFramework(path: "/test/DynamicB.xcframework", linking: .dynamic)
        let staticSwiftA = GraphDependency.testXCFramework(
            path: staticSwiftAPath,
            linking: .static,
            swiftModules: [staticSwiftAPath.appending(component: "StaticSwiftA.swiftmodule")]
        )
        let staticSwiftB = GraphDependency.testXCFramework(
            path: staticSwiftBPath,
            linking: .static,
            swiftModules: [staticSwiftBPath.appending(component: "StaticSwiftB.swiftmodule")]
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set([dynamicA, dynamicB]),
            dynamicA: Set([staticSwiftA, dynamicB]),
            dynamicB: Set([staticSwiftB]),
        ]
        let graph = Graph.test(projects: [project.path: project], dependencies: dependencies)
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.staticXCFrameworksLinkedByDynamicXCFrameworkDependencies(path: project.path, name: target.name)

        // Then
        #expect(got == Set([staticSwiftA, staticSwiftB]))
        // Repeated so the memoized per-root walks are exercised on a warm cache too.
        #expect(
            subject.staticXCFrameworksLinkedByDynamicXCFrameworkDependencies(path: project.path, name: target.name)
                == Set([staticSwiftA, staticSwiftB])
        )
    }

    @Test(arguments: [
        (.static, .static, .when([.ios, .macos])),
        (.static, .dynamic, .when([.ios])),
        (.dynamic, .static, .when([.ios, .macos])),
        (.dynamic, .dynamic, .when([.ios, .macos])),
    ] as [(BinaryLinking, BinaryLinking, PlatformCondition?)])
    func linkableDependenciesRespectXCFrameworkLinkBoundaries(
        linking: BinaryLinking, wrapperLinking: BinaryLinking, expectedCondition: PlatformCondition?
    ) throws {
        let target = Target.test(name: "App", destinations: [.iPhone, .mac])
        let project = Project.test(targets: [target])
        let app = GraphDependency.target(name: target.name, path: project.path)
        let framework = GraphDependency.testXCFramework(path: "/SDK.xcframework", linking: linking)
        let wrapper = GraphDependency.testXCFramework(path: "/Wrapper.xcframework", linking: wrapperLinking)
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [app: [framework, wrapper], wrapper: [framework]],
            dependencyConditions: [
                GraphEdge(from: app, to: framework): try #require(.when([.ios])),
                GraphEdge(from: app, to: wrapper): try #require(.when([.macos])),
            ]
        )

        let references = try GraphTraverser(graph: graph).linkableDependencies(path: project.path, name: target.name)
        let frameworks = references.filter {
            if case let .xcframework(path, _, _, _, _) = $0 { return path == "/SDK.xcframework" }
            return false
        }

        #expect(frameworks == [
            .xcframework(
                path: "/SDK.xcframework",
                expectedSignature: nil,
                infoPlist: .test(),
                status: .required,
                condition: expectedCondition
            ),
        ])
    }
}
