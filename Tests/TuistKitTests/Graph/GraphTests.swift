import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

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

final class GraphTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_frameworks() throws {
        let framework = FrameworkNode(path: AbsolutePath("/path/to/framework.framework"))
        let cache = GraphLoaderCache()
        cache.add(precompiledNode: framework)
        let graph = Graph.test(cache: cache)
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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let dependencies = graph.targetDependencies(path: project.path,
                                                    name: target.name)
        XCTAssertEqual(dependencies.first?.target.name, "Dependency")
    }

    func test_linkableDependencies_whenPrecompiled() throws {
        let target = Target.test(name: "Main")
        let precompiledNode = FrameworkNode(path: AbsolutePath("/test/test.framework"))
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name)
        XCTAssertEqual(got.first, .absolute(precompiledNode.path))
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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name)
        XCTAssertEqual(got.first, .product("libDependency.a"))
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

        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        cache.add(targetNode: dependencyNode)
        cache.add(targetNode: staticDependencyNode)

        let graph = Graph.test(cache: cache)
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first, .product("Dependency.framework"))

        let frameworkGot = try graph.linkableDependencies(path: project.path,
                                                          name: dependency.name)

        XCTAssertEqual(frameworkGot.count, 1)
        XCTAssertTrue(frameworkGot.contains(.product("libStaticDependency.a")))
    }

    func test_librariesPublicHeaders() throws {
        let target = Target.test(name: "Main")
        let publicHeadersPath = AbsolutePath("/test/public/")
        let precompiledNode = LibraryNode(path: AbsolutePath("/test/test.a"),
                                          publicHeaders: publicHeadersPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let got = graph.librariesPublicHeadersFolders(path: project.path,
                                                      name: target.name)
        XCTAssertEqual(got.first, publicHeadersPath)
    }

    func test_embeddableFrameworks_when_targetIsNotApp() throws {
        let target = Target.test(name: "Main", product: .framework)
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        system.succeedCommand([], output: "dynamically linked")

        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        XCTAssertNil(got.first)
    }

    func test_embeddableFrameworks_when_dependencyIsATarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand([], output: "dynamically linked")
        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)
        XCTAssertEqual(got.first, DependencyReference.product("Dependency.framework"))
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        let frameworkPath = AbsolutePath("/test/test.framework")
        let target = Target.test(name: "Main")
        let frameworkNode = FrameworkNode(path: frameworkPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [frameworkNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand("/usr/bin/file", "/test/test.framework/test",
                              output: "dynamically linked")

        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        XCTAssertEqual(got.first, DependencyReference.absolute(frameworkPath))
    }

    func test_embeddableFrameworks_when_dependencyIsATransitiveFramework() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        let frameworkPath = AbsolutePath("/test/test.framework")
        let frameworkNode = FrameworkNode(path: frameworkPath)

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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand([], output: "dynamically linked")
        let got = try graph.embeddableFrameworks(
            path: project.path,
            name: target.name,
            system: system
        )

        XCTAssertEqual(got, [
            DependencyReference.product("Dependency.framework"),
            DependencyReference.absolute(frameworkPath),
        ])
    }

    func test_librariesSearchPaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNode = LibraryNode(path: AbsolutePath("/test/test.a"),
                                          publicHeaders: AbsolutePath("/test/public/"))
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = graph.librariesSearchPaths(path: project.path,
                                             name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test")])
    }

    func test_librariesSwiftIncludePaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNodeA = LibraryNode(path: AbsolutePath("/test/test.a"),
                                           publicHeaders: AbsolutePath("/test/public/"),
                                           swiftModuleMap: AbsolutePath("/test/modules/test.swiftmodulemap"))
        let precompiledNodeB = LibraryNode(path: AbsolutePath("/test/another.a"),
                                           publicHeaders: AbsolutePath("/test/public/"),
                                           swiftModuleMap: nil)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNodeA, precompiledNodeB])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = graph.librariesSwiftIncludePaths(path: project.path,
                                                   name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test/modules")])
    }
}
