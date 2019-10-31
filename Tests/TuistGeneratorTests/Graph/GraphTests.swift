import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting
@testable import TuistGenerator

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

        system.succeedCommand("/usr/bin/lipo", "-info", "/test/test.framework/test",
                              output: "Architectures in the fat file: Alamofire are: x86_64 arm64")

        let got = try graph.linkableDependencies(path: project.path, name: target.name)
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

        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        cache.add(targetNode: dependencyNode)
        cache.add(targetNode: staticDependencyNode)

        let graph = Graph.test(cache: cache)
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
        XCTAssertEqual(result, [DependencyReference.product(target: "DynamicFramework", productName: "DynamicFramework.framework"),
                                DependencyReference.product(target: "StaticFramework", productName: "StaticFramework.framework")])
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
            DependencyReference.product(target: "DynamicFramework1", productName: "DynamicFramework1.framework"),
        ])
        XCTAssertEqual(dynamicFramework1Result, [
            DependencyReference.product(target: "DynamicFramework2", productName: "DynamicFramework2.framework"),
            DependencyReference.product(target: "StaticFramework1", productName: "libStaticFramework1.a"),
            DependencyReference.product(target: "StaticFramework2", productName: "libStaticFramework2.a"),
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
        XCTAssertEqual(dynamicFramework1Result, [DependencyReference.product(target: "DynamicFramework2", productName: "DynamicFramework2.framework")])
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
                                                 name: target.name)

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
                                                 name: target.name)
        XCTAssertEqual(got.first, DependencyReference.product(target: "Dependency", productName: "Dependency.framework"))
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        let frameworkPath = AbsolutePath("/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
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

        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

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

        system.succeedCommand("/usr/bin/file", "/test/test.framework/test",
                              output: "dynamically linked")

        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

        XCTAssertEqual(got, [
            DependencyReference.product(target: "Dependency", productName: "Dependency.framework"),
            DependencyReference.absolute(frameworkPath),
        ])
    }

    func test_embeddableFrameworks_when_precompiledStaticFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        let frameworkNode = FrameworkNode(path: "/test/StaticFramework.framework")
        let targetNode = TargetNode(
            project: project,
            target: target,
            dependencies: [frameworkNode]
        )
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand("/usr/bin/file", "/test/StaticFramework.framework/StaticFramework",
                              output: "current ar archive random library")

        // When
        let result = try graph.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertTrue(result.isEmpty)
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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = try graph.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        let expected = dependencyNames.sorted().map { DependencyReference.product(target: $0, productName: "\($0).framework") }
        XCTAssertEqual(got, expected)
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

    func test_packageDepedencies_fromTargetDependency() throws {
        // Given
        let target = Target.test(name: "Test", product: .app, dependencies: [
            .package(product: "A"),
            .package(product: "B"),
        ])
        let project = Project.test(path: "/path", packages: [
            .remote(url: "testA", requirement: .branch("master")),
            .local(path: AbsolutePath("/testB")),
        ])

        let graph = Graph.create(project: project,
                                 dependencies: [(target: target, dependencies: [])])

        // When
        let result = try graph.packages(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(result.first?.name, "testA")
        XCTAssertEqual(result.last?.name, "/testB")
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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

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
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        let got = graph.appExtensionDependencies(path: project.path, name: target.name)

        XCTAssertEqual(got.first?.name, "StickerPackExtension")
    }

    func test_encode() {
        // Given
        System.shared = System()
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let framework = FrameworkNode(path: fixturePath(path: RelativePath("xpm.framework")))
        let library = LibraryNode(path: fixturePath(path: RelativePath("libStaticLibrary.a")),
                                  publicHeaders: fixturePath(path: RelativePath("")))
        let target = TargetNode.test(dependencies: [framework, library])
        cache.add(targetNode: target)
        cache.add(precompiledNode: framework)
        cache.add(precompiledNode: library)

        let expected = """
        [
            {
              "path" : "\(library.path)",
              "architectures" : [
                "x86_64"
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
            },
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
            }
        ]
        """

        // Then
        XCTAssertEncodableEqualToJson(graph, expected)
    }

    // MARK: - Helpers

    private func sdkDependency(from dependency: DependencyReference) -> SDKPathAndStatus? {
        switch dependency {
        case let .sdk(path, status):
            return SDKPathAndStatus(name: path.basename, status: status)
        default:
            return nil
        }
    }
}

final class DependencyReferenceTests: XCTestCase {
    func test_equal() {
        let subjects: [(DependencyReference, DependencyReference, Bool)] = [
            // Absolute
            (.absolute(.init("/a.framework")), .absolute(.init("/a.framework")), true),
            (.absolute(.init("/a.framework")), .product(target: "Main", productName: "Main.app"), false),
            (.absolute(.init("/a.framework")), .sdk(.init("/CoreData.framework"), .required), false),

            // Product
            (.product(target: "Main", productName: "Main.app"), .product(target: "Main", productName: "Main.app"), true),
            (.product(target: "Main", productName: "Main.app"), .absolute(.init("/a.framework")), false),
            (.product(target: "Main", productName: "Main.app"), .sdk(.init("/CoreData.framework"), .required), false),
            (.product(target: "Main-iOS", productName: "Main.app"), .product(target: "Main-macOS", productName: "Main.app"), false),

            // SDK
            (.sdk(.init("/CoreData.framework"), .required), .sdk(.init("/CoreData.framework"), .required), true),
            (.sdk(.init("/CoreData.framework"), .required), .product(target: "Main", productName: "Main.app"), false),
            (.sdk(.init("/CoreData.framework"), .required), .absolute(.init("/a.framework")), false),
        ]

        XCTAssertEqualPairs(subjects)
    }

    func test_compare() {
        XCTAssertFalse(DependencyReference.absolute("/A") < .absolute("/A"))
        XCTAssertTrue(DependencyReference.absolute("/A") < .absolute("/B"))
        XCTAssertFalse(DependencyReference.absolute("/B") < .absolute("/A"))

        XCTAssertFalse(DependencyReference.product(target: "A", productName: "A.framework") < .product(target: "A", productName: "A.framework"))
        XCTAssertTrue(DependencyReference.product(target: "A", productName: "A.framework") < .product(target: "B", productName: "B.framework"))
        XCTAssertFalse(DependencyReference.product(target: "B", productName: "B.framework") < .product(target: "A", productName: "A.framework"))
        XCTAssertTrue(DependencyReference.product(target: "A", productName: "A.app") < .product(target: "A", productName: "A.framework"))

        XCTAssertTrue(DependencyReference.product(target: "/A", productName: "A.framework") < .absolute("/A"))
        XCTAssertTrue(DependencyReference.product(target: "/A", productName: "A.framework") < .absolute("/B"))
        XCTAssertTrue(DependencyReference.product(target: "/B", productName: "B.framework") < .absolute("/A"))

        XCTAssertFalse(DependencyReference.absolute("/A") < .product(target: "/A", productName: "A.framework"))
        XCTAssertFalse(DependencyReference.absolute("/A") < .product(target: "/B", productName: "B.framework"))
        XCTAssertFalse(DependencyReference.absolute("/B") < .product(target: "/A", productName: "A.framework"))
    }

    func test_compare_isStable() {
        // Given
        let subject: [DependencyReference] = [
            .absolute("/A"),
            .absolute("/B"),
            .product(target: "A", productName: "A.framework"),
            .product(target: "B", productName: "B.framework"),
            .sdk("/A.framework", .required),
            .sdk("/B.framework", .optional),
        ]

        // When
        let sorted = (0 ..< 10).map { _ in subject.shuffled().sorted() }

        // Then
        let unstable = sorted.dropFirst().filter { $0 != sorted.first }
        XCTAssertTrue(unstable.isEmpty)
    }
}

private struct SDKPathAndStatus: Equatable {
    var name: String
    var status: SDKStatus
}
