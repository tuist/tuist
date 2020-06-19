import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupport
@testable import TuistSupportTesting

final class GraphErrorTests: XCTestCase {
    func test_description_when_unsupportedFileExtension() {
        let error = GraphError.unsupportedFileExtension("type")
        let description = "Could't obtain product file extension for product type: type"
        XCTAssertEqual(error.description, description)
    }

    func test_type_when_unsupportedFileExtension() {
        let error = GraphError.unsupportedFileExtension("type")
        XCTAssertEqual(error.type, .bug)
    }
}

final class GraphTests: TuistUnitTestCase {
    func test_frameworks() throws {
        let framework = FrameworkNode.test(path: AbsolutePath("/path/to/framework.framework"))
        let graph = Graph.test(precompiled: [framework])
        XCTAssertTrue(graph.frameworks.contains(framework))
    }

    func test_targetDependencies() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target, dependency])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(targets: [targetNode.path: [targetNode]])
        let dependencies = graph.targetDependencies(path: project.path,
                                                    name: target.name)
        XCTAssertEqual(dependencies.first?.target.name, "Dependency")
    }

    func test_testTargetsDependingOn() throws {
        // given
        let target = Target.test(name: "Main")
        let dependentTarget = Target.test(name: "Dependency", product: .staticLibrary)
        let testTarget1 = Target.test(name: "MainTests1", product: .unitTests)
        let testTarget2 = Target.test(name: "MainTests2", product: .unitTests)
        let testTarget3 = Target.test(name: "MainTests3", product: .unitTests)
        let testTargets = [testTarget1, testTarget2, testTarget3]
        let project = Project.test(targets: [target, dependentTarget] + testTargets)

        let dependencyNode = TargetNode(project: project, target: dependentTarget, dependencies: [])
        let targetNode = TargetNode(project: project, target: target, dependencies: [dependencyNode])
        let testsNodes = testTargets.map { TargetNode(project: project, target: $0, dependencies: [targetNode]) }

        let targets = testsNodes.reduce(into: [project.path: [targetNode, dependencyNode]]) {
            $0[project.path]?.append($1)
        }
        let graph = Graph.test(projects: [project], targets: targets)

        // when
        let testDependencies = graph.testTargetsDependingOn(path: project.path, name: target.name)

        // then
        let testDependenciesNames = try XCTUnwrap(testDependencies).map { $0.name }
        XCTAssertEqual(testDependenciesNames.count, 3)
        XCTAssertEqual(testDependenciesNames, ["MainTests1", "MainTests2", "MainTests3"])
    }

    func test_linkableDependencies_whenPrecompiled() throws {
        let target = Target.test(name: "Main")
        let precompiledNode = FrameworkNode.test(path: AbsolutePath("/test/test.framework"))
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(targets: [targetNode.path: [targetNode]])

        let got = try graph.linkableDependencies(path: project.path, name: target.name)
        XCTAssertEqual(got.first, GraphDependencyReference(precompiledNode: precompiledNode))
    }

    func test_linkableDependencies_whenALibraryTarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [dependencyNode, targetNode],
        ])

        let got = try graph.linkableDependencies(path: project.path, name: target.name)
        XCTAssertEqual(got.first, .product(target: "Dependency", productName: "libDependency.a"))
    }

    func test_linkableDependencies_whenAFrameworkTarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        let staticDependencyNode = TargetNode(project: project,
                                              target: staticDependency,
                                              dependencies: [])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [staticDependencyNode])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])

        let graph = Graph.test(projects: [project], targets: [project.path: [targetNode, dependencyNode, staticDependencyNode]])
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first, .product(target: "Dependency", productName: "Dependency.framework"))

        let frameworkGot = try graph.linkableDependencies(path: project.path, name: dependency.name)

        XCTAssertEqual(frameworkGot.count, 1)
        XCTAssertTrue(frameworkGot.contains(.product(target: "StaticDependency", productName: "libStaticDependency.a")))
    }

    func test_linkableDependencies_transitiveDynamicLibrariesOneStaticHop() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .staticFramework,
                                          dependencies: [])
        let dynamicFramework = Target.test(name: "DynamicFramework",
                                           product: .framework,
                                           dependencies: [])

        let app = Target.test(name: "App", product: .app)

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: [dynamicFramework]),
                                     (target: dynamicFramework, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: app.name)

        // Then
        XCTAssertEqual(result, [GraphDependencyReference.product(target: "DynamicFramework", productName: "DynamicFramework.framework"),
                                GraphDependencyReference.product(target: "StaticFramework", productName: "StaticFramework.framework")])
    }

    func test_linkableDependencies_transitiveDynamicLibrariesThreeHops() throws {
        // Given
        let dynamicFramework1 = Target.test(name: "DynamicFramework1",
                                            product: .framework,
                                            dependencies: [])
        let dynamicFramework2 = Target.test(name: "DynamicFramework2",
                                            product: .framework,
                                            dependencies: [])
        let staticFramework1 = Target.test(name: "StaticFramework1",
                                           product: .staticLibrary,
                                           dependencies: [])
        let staticFramework2 = Target.test(name: "StaticFramework2",
                                           product: .staticLibrary,
                                           dependencies: [])

        let app = Target.test(name: "App", product: .app)

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework1]),
                                     (target: dynamicFramework1, dependencies: [staticFramework1]),
                                     (target: staticFramework1, dependencies: [staticFramework2]),
                                     (target: staticFramework2, dependencies: [dynamicFramework2]),
                                     (target: dynamicFramework2, dependencies: []),
                                 ])

        // When
        let appResult = try graph.linkableDependencies(path: projectA.path, name: app.name)
        let dynamicFramework1Result = try graph.linkableDependencies(path: projectA.path, name: dynamicFramework1.name)

        // Then
        XCTAssertEqual(appResult, [
            GraphDependencyReference.product(target: "DynamicFramework1", productName: "DynamicFramework1.framework"),
        ])
        XCTAssertEqual(dynamicFramework1Result, [
            GraphDependencyReference.product(target: "DynamicFramework2", productName: "DynamicFramework2.framework"),
            GraphDependencyReference.product(target: "StaticFramework1", productName: "libStaticFramework1.a"),
            GraphDependencyReference.product(target: "StaticFramework2", productName: "libStaticFramework2.a"),
        ])
    }

    func test_linkableDependencies_transitiveDynamicLibrariesCheckNoDuplicatesInParentDynamic() throws {
        // Given
        let dynamicFramework1 = Target.test(name: "DynamicFramework1",
                                            product: .framework,
                                            dependencies: [])
        let dynamicFramework2 = Target.test(name: "DynamicFramework2",
                                            product: .framework,
                                            dependencies: [])
        let dynamicFramework3 = Target.test(name: "DynamicFramework3",
                                            product: .framework,
                                            dependencies: [])
        let staticFramework1 = Target.test(name: "StaticFramework1",
                                           product: .staticLibrary,
                                           dependencies: [])
        let staticFramework2 = Target.test(name: "StaticFramework2",
                                           product: .staticLibrary,
                                           dependencies: [])

        let app = Target.test(name: "App", product: .app)

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework1]),
                                     (target: dynamicFramework1, dependencies: [dynamicFramework2]),
                                     (target: dynamicFramework2, dependencies: [staticFramework1]),
                                     (target: staticFramework1, dependencies: [staticFramework2]),
                                     (target: staticFramework2, dependencies: [dynamicFramework3]),
                                     (target: dynamicFramework3, dependencies: []),
                                 ])

        // When
        let dynamicFramework1Result = try graph.linkableDependencies(path: projectA.path, name: dynamicFramework1.name)

        // Then
        XCTAssertEqual(dynamicFramework1Result, [GraphDependencyReference.product(target: "DynamicFramework2", productName: "DynamicFramework2.framework")])
    }

    func test_linkableDependencies_transitiveSDKDependenciesStatic() throws {
        // Given
        let staticFrameworkA = Target.test(name: "StaticFrameworkA",
                                           product: .staticFramework,
                                           dependencies: [.sdk(name: "some.framework", status: .optional)])
        let staticFrameworkB = Target.test(name: "StaticFrameworkB",
                                           product: .staticFramework,
                                           dependencies: [])

        let app = Target.test(name: "App", product: .app)

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkA, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: app.name)

        // Then
        XCTAssertEqual(result.compactMap(sdkDependency), [
            SDKPathAndStatus(name: "some.framework", status: .optional),
        ])
    }

    func test_linkableDependencies_transitiveSDKDependenciesDynamic() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .staticFramework,
                                          dependencies: [.sdk(name: "some.framework", status: .optional)])
        let dynamicFramework = Target.test(name: "DynamicFramework",
                                           product: .framework,
                                           dependencies: [])

        let app = Target.test(name: "App", product: .app)

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework]),
                                     (target: dynamicFramework, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let appResult = try graph.linkableDependencies(path: projectA.path, name: app.name)
        let dynamicResult = try graph.linkableDependencies(path: projectA.path, name: dynamicFramework.name)

        // Then
        XCTAssertEqual(appResult.compactMap(sdkDependency), [])
        XCTAssertEqual(dynamicResult.compactMap(sdkDependency),
                       [SDKPathAndStatus(name: "some.framework", status: .optional)])
    }

    func test_linkableDependencies_transitiveSDKDependenciesNotDuplicated() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .staticFramework,
                                          dependencies: [.sdk(name: "some.framework", status: .optional)])
        let app = Target.test(name: "App",
                              product: .app,
                              dependencies: [.sdk(name: "some.framework", status: .optional)])

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: app.name)

        // Then
        XCTAssertEqual(result.compactMap(sdkDependency), [SDKPathAndStatus(name: "some.framework", status: .optional)])
    }

    func test_linkableDependencies_transitiveSDKDependenciesImmediateDependencies() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFrameworkA",
                                          product: .staticFramework,
                                          dependencies: [.sdk(name: "thingone.framework", status: .optional),
                                                         .sdk(name: "thingtwo.framework", status: .required)])

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: staticFramework.name)

        // Then
        XCTAssertEqual(result.compactMap(sdkDependency),
                       [SDKPathAndStatus(name: "thingone.framework", status: .optional),
                        SDKPathAndStatus(name: "thingtwo.framework", status: .required)])
    }

    func test_linkableDependencies_NoTransitiveSDKDependenciesForStaticFrameworks() throws {
        // Given
        let staticFrameworkA = Target.test(name: "StaticFrameworkA",
                                           product: .staticFramework,
                                           dependencies: [.sdk(name: "ThingOne.framework", status: .optional)])
        let staticFrameworkB = Target.test(name: "StaticFrameworkB",
                                           product: .staticFramework,
                                           dependencies: [.sdk(name: "ThingTwo.framework", status: .optional)])

        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: staticFrameworkA.name)

        // Then
        XCTAssertEqual(result.compactMap(sdkDependency),
                       [SDKPathAndStatus(name: "ThingOne.framework", status: .optional)])
    }

    func test_linkableDependencies_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: project.path, name: watchExtension.name)

        // Then
        XCTAssertEqual(result, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework"),
        ])
    }

    func test_linkableDependencies_when_watchExtension_staticDependency() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .staticFramework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: project.path, name: watchExtension.name)

        // Then
        XCTAssertEqual(result, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework"),
            .product(target: "FrameworkB", productName: "FrameworkB.framework"),
        ])
    }

    func test_linkableDependencies_whenHostedTestTarget_withCommonStaticProducts() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .staticFramework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                     (target: tests, dependencies: [app, staticFramework]),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: tests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_linkableDependencies_whenHostedTestTarget_withCommonDynamicProducts() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app, framework]),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: tests.name)

        // Then
        XCTAssertEqual(result, [
            .product(target: "Framework", productName: "Framework.framework"),
        ])
    }

    func test_linkableDependencies_whenHostedTestTarget_doNotIncludeRedundantDependencies() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app]),
                                 ])

        // When
        let result = try graph.linkableDependencies(path: projectA.path, name: tests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_librariesPublicHeaders() throws {
        let target = Target.test(name: "Main")
        let publicHeadersPath = AbsolutePath("/test/public/")
        let precompiledNode = LibraryNode.test(path: AbsolutePath("/test/test.a"),
                                               publicHeaders: publicHeadersPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNode],
                               targets: [project.path: [targetNode]])
        let got = graph.librariesPublicHeadersFolders(path: project.path,
                                                      name: target.name)
        XCTAssertEqual(got.first, publicHeadersPath)
    }

    func test_embeddableFrameworks_when_targetIsNotApp() throws {
        // Given
        let target = Target.test(name: "Main", product: .framework)
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])
        system.succeedCommand([], output: "dynamically linked")

        // When
        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name)

        // Then
        XCTAssertNil(got.first)
    }

    func test_embeddableFrameworks_when_dependencyIsATarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project],
                               targets: [project.path: [targetNode, dependencyNode]])

        // When
        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name)

        // Then
        XCTAssertEqual(got.first, GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework"))
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        // Given
        let frameworkPath = AbsolutePath("/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
        let frameworkNode = FrameworkNode.test(path: frameworkPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [frameworkNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [frameworkNode],
                               targets: [project.path: [targetNode]])

        // When
        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(got.first, GraphDependencyReference(precompiledNode: frameworkNode))
    }

    func test_embeddableFrameworks_when_transitiveXCFrameworks() throws {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let project = Project.test(targets: [app])

        let dNode = XCFrameworkNode.test(path: "/xcframeworks/d.xcframework")
        let cNode = XCFrameworkNode.test(path: "/xcframeworks/c.xcframework", dependencies: [.xcframework(dNode)])
        let appNode = TargetNode.test(target: app, dependencies: [cNode])

        let cache = GraphLoaderCache()
        cache.add(targetNode: appNode)
        cache.add(precompiledNode: dNode)
        cache.add(precompiledNode: cNode)
        let graph = Graph.test(entryNodes: [appNode],
                               projects: [project],
                               precompiled: [cNode, dNode],
                               targets: [project.path: [appNode]])

        // When
        let got = try graph.embeddableFrameworks(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(precompiledNode: cNode),
            GraphDependencyReference(precompiledNode: dNode),
        ])
    }

    func test_embeddableFrameworks_when_dependencyIsATransitiveFramework() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        let frameworkPath = AbsolutePath("/test/test.framework")
        let frameworkNode = FrameworkNode.test(path: frameworkPath)

        let dependencyNode = TargetNode(
            project: project,
            target: dependency,
            dependencies: [frameworkNode]
        )
        let targetNode = TargetNode(
            project: project,
            target: target,
            dependencies: [dependencyNode]
        )
        let graph = Graph.test(projects: [project],
                               precompiled: [frameworkNode],
                               targets: [project.path: [targetNode, dependencyNode]])

        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

        XCTAssertEqual(got, [
            GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework"),
            GraphDependencyReference(precompiledNode: frameworkNode),
        ])
    }

    func test_embeddableFrameworks_when_precompiledStaticFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        let frameworkNode = FrameworkNode.test(path: "/test/StaticFramework.framework", linking: .static)
        let targetNode = TargetNode(
            project: project,
            target: target,
            dependencies: [frameworkNode]
        )

        let graph = Graph.test(projects: [project],
                               precompiled: [frameworkNode],
                               targets: [project.path: [targetNode]])

        // When
        let result = try graph.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_embeddableFrameworks_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])

        // When
        let result = try graph.embeddableFrameworks(path: project.path, name: watchExtension.name)

        // Then
        XCTAssertEqual(result, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework"),
            .product(target: "FrameworkB", productName: "FrameworkB.framework"),
        ])
    }

    func test_embeddableFrameworks_ordered() throws {
        // Given
        let dependencyNames = (0 ..< 10).shuffled().map { "Dependency\($0)" }
        let target = Target.test(name: "Main", product: .app)
        let project = Project.test(targets: [target])
        let dependencyNodes = dependencyNames.map {
            TargetNode(project: project,
                       target: Target.test(name: $0, product: .framework),
                       dependencies: [])
        }
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: dependencyNodes)
        let targetNodes = dependencyNodes.reduce(into: [project.path: [targetNode]]) { $0[project.path]?.append($1) }
        let graph = Graph.test(projects: [project], targets: targetNodes)

        // When
        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        let expected = dependencyNames.sorted().map { GraphDependencyReference.product(target: $0, productName: "\($0).framework") }
        XCTAssertEqual(got, expected)
    }

    func test_embeddableDependencies_whenHostedTestTarget() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app]),
                                 ])

        // When
        let result = try graph.embeddableFrameworks(path: projectA.path, name: tests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_embeddableDependencies_when_nonHostedTestTarget_dynamic_dependencies() throws {
        // Given
        let precompiledNode = mockDynamicFrameworkNode(at: AbsolutePath("/test/test.framework"))
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        let unitTestsNode = TargetNode(project: project, target: unitTests, dependencies: [precompiledNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(targetNode: unitTestsNode)

        let graph = Graph(name: "Graph",
                          entryPath: project.path,
                          cache: cache,
                          entryNodes: [unitTestsNode])

        // When
        let result = try graph.embeddableFrameworks(path: project.path, name: unitTests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_embeddableDependencies_whenHostedTestTarget_transitiveDepndencies() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: framework, dependencies: []),
                                     (target: staticFramework, dependencies: [framework]),
                                     (target: tests, dependencies: [app, staticFramework]),
                                 ])

        // When
        let result = try graph.embeddableFrameworks(path: projectA.path, name: tests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_embeddableDependencies_whenUITest_andAppPrecompiledDepndencies() throws {
        // Given
        let precompiledNode = mockDynamicFrameworkNode(at: AbsolutePath("/test/test.framework"))
        let app = Target.test(name: "App", product: .app)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let project = Project.test(path: "/path/a")

        let appNode = TargetNode(project: project, target: app, dependencies: [precompiledNode])
        let uiTestsNode = TargetNode(project: project, target: uiTests, dependencies: [appNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(targetNode: appNode)
        cache.add(targetNode: uiTestsNode)

        let graph = Graph(name: "Graph",
                          entryPath: project.path,
                          cache: cache,
                          entryNodes: [appNode, uiTestsNode])

        // When
        let result = try graph.embeddableFrameworks(path: project.path, name: uiTests.name)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_runPathSearchPaths() throws {
        // Given
        let precompiledNode = mockDynamicFrameworkNode(at: AbsolutePath("/test/test.framework"))
        let precompiledNodeB = mockDynamicFrameworkNode(at: AbsolutePath("/test/test.framework"))
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        let unitTestsNode = TargetNode(project: project, target: unitTests, dependencies: [precompiledNode, precompiledNodeB])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(precompiledNode: precompiledNodeB)
        cache.add(targetNode: unitTestsNode)

        let graph = Graph(name: "Graph",
                          entryPath: project.path,
                          cache: cache,
                          entryNodes: [unitTestsNode])

        // When
        let got = graph.runPathSearchPaths(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(
            got,
            [AbsolutePath("/path/to")]
        )
    }

    func test_runPathSearchPaths_when_unit_tests_with_hosted_target() throws {
        // Given
        let precompiledNode = mockDynamicFrameworkNode(at: AbsolutePath("/test/test.framework"))
        let app = Target.test(name: "App", product: .app)
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        let appNode = TargetNode(project: project, target: app, dependencies: [precompiledNode])
        let unitTestsNode = TargetNode(project: project, target: unitTests, dependencies: [appNode, precompiledNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(targetNode: appNode)
        cache.add(precompiledNode: precompiledNode)
        cache.add(targetNode: unitTestsNode)

        let graph = Graph(name: "Graph",
                          entryPath: project.path,
                          cache: cache,
                          entryNodes: [unitTestsNode])

        // When
        let got = graph.runPathSearchPaths(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEmpty(got)
    }

    func test_librariesSearchPaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNode = LibraryNode.test(path: "/test/test.a", publicHeaders: "/test/public/")
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNode],
                               targets: [project.path: [targetNode]])

        // When
        let got = graph.librariesSearchPaths(path: project.path,
                                             name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test")])
    }

    func test_librariesSwiftIncludePaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNodeA = LibraryNode.test(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap")
        let precompiledNodeB = LibraryNode.test(path: "/test/another.a", swiftModuleMap: nil)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNodeA, precompiledNodeB])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNodeA, precompiledNodeB],
                               targets: [project.path: [targetNode]])

        // When
        let got = graph.librariesSwiftIncludePaths(path: project.path,
                                                   name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test/modules")])
    }

    func test_resourceBundleDependencies_fromTargetDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let app = Target.test(name: "App", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: app, dependencies: [bundle]),
                                 ])

        // When
        let result = graph.resourceBundleDependencies(path: projectA.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.target.name), [
            "Bundle1",
        ])
    }

    func test_resourceBundleDependencies_fromProjectDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectA, target: bundle, dependencies: []),
                                     (project: projectB, target: app, dependencies: [bundle]),
                                 ])

        // When
        let result = graph.resourceBundleDependencies(path: projectB.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.target.name), [
            "Bundle1",
        ])
    }

    func test_appExtensionDependencies_when_dependencyIsAppExtension() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "AppExtension", product: .appExtension)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])

        let got = graph.appExtensionDependencies(path: project.path, name: target.name)

        XCTAssertEqual(got.first?.name, "AppExtension")
    }

    func test_appExtensionDependencies_when_dependencyIsStickerPackExtension() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])

        let got = graph.appExtensionDependencies(path: project.path, name: target.name)

        XCTAssertEqual(got.first?.name, "StickerPackExtension")
    }

    func test_hostTargetNode_watchApp() {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let project = Project.test(path: "/path/a")

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [watchApp]),
                                     (target: watchApp, dependencies: []),
                                 ])

        // When
        let result = graph.hostTargetNodeFor(path: project.path, name: "WatchApp")

        // Then
        XCTAssertEqual(result?.target, app)
    }

    func test_hostTargetNode_watchAppExtension() {
        // Given
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let watchAppExtension = Target.test(name: "WatchAppExtension", platform: .watchOS, product: .watch2Extension)
        let project = Project.test(path: "/path/a")

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchApp, dependencies: [watchAppExtension]),
                                     (target: watchAppExtension, dependencies: []),
                                 ])

        // When
        let result = graph.hostTargetNodeFor(path: project.path, name: "WatchAppExtension")

        // Then
        XCTAssertEqual(result?.target, watchApp)
    }

    func test_encode() {
        // Given
        System.shared = System()
        let project = Project.test()
        let framework = FrameworkNode.test(path: fixturePath(path: RelativePath("xpm.framework")), architectures: [.x8664, .arm64])
        let library = LibraryNode.test(path: fixturePath(path: RelativePath("libStaticLibrary.a")),
                                       publicHeaders: fixturePath(path: RelativePath("")))
        let target = TargetNode.test(dependencies: [framework, library])

        let graph = Graph.test(projects: [project],
                               precompiled: [framework, library],
                               targets: [project.path: [target]])

        let expected = """
        [
        {
            "product" : "\(target.target.product.rawValue)",
            "bundle_id" : "\(target.target.bundleId)",
            "platform" : "\(target.target.platform.rawValue)",
            "path" : "\(target.path)",
            "dependencies" : [
                "xpm",
                "libStaticLibrary"
            ],
            "name" : "Target",
            "type" : "source"
        },
        {
            "path" : "\(library.path)",
            "architectures" : [
                "arm64"
            ],
            "product" : "static_library",
            "name" : "\(library.name)",
            "type" : "precompiled"
        },
            {
                "path" : "\(framework.path)",
                "architectures" : [
                    "x86_64",
                    "arm64"
                ],
                "product" : "framework",
                "name" : "\(framework.name)",
                "type" : "precompiled"
            }
        ]
        """

        // Then
        XCTAssertEncodableEqualToJson(graph, expected)
    }

    // MARK: - Helpers

    private func mockDynamicFrameworkNode(at path: AbsolutePath) -> FrameworkNode {
        let precompiledNode = FrameworkNode.test()
        let binaryPath = path.appending(component: path.basenameWithoutExt)
        system.succeedCommand("/usr/bin/file",
                              binaryPath.pathString,
                              output: "dynamically linked")
        return precompiledNode
    }

    private func sdkDependency(from dependency: GraphDependencyReference) -> SDKPathAndStatus? {
        switch dependency {
        case let .sdk(path, status, _):
            return SDKPathAndStatus(name: path.basename, status: status)
        default:
            return nil
        }
    }
}

private struct SDKPathAndStatus: Equatable {
    var name: String
    var status: SDKStatus
}
