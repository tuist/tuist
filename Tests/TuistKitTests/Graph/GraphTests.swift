import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

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
        XCTAssertEqual(dependencies.first, "Dependency")
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
        XCTAssertEqual(got.first, .product("Dependency.a"))
    }

    func test_linkableDependencies_whenAFrameworkTarget() throws {
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
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name)
        XCTAssertEqual(got.first, .product("Dependency.framework"))
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
        system.stub(args: [], stderror: nil, stdout: "dynamically linked", exitstatus: 0)

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

        system.stub(args: [], stderror: nil, stdout: "dynamically linked", exitstatus: 0)
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

        system.stub(args: ["/usr/bin/file", "/test/test.framework/test"],
                    stderror: nil,
                    stdout: "dynamically linked",
                    exitstatus: 0)

        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        XCTAssertEqual(got.first, DependencyReference.absolute(frameworkPath))
    }
}
