import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphTraverserTests: TuistUnitTestCase {
    func test_directTargetDependencies() {
        // Given
        // A -> B -> C
        let project = Project.test()
        let a = Target.test(name: "A")
        let b = Target.test(name: "B")
        let c = Target.test(name: "C")
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: a.name, path: project.path): Set([.target(name: b.name, path: project.path)]),
            .target(name: b.name, path: project.path): Set([.target(name: c.name, path: project.path)]),
        ]
        let targets: [AbsolutePath: [String: Target]] = [project.path: [
            a.name: a,
            b.name: b,
            c.name: c,
        ]]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: targets,
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.directTargetDependencies(path: project.path, name: a.name)

        // Then
        XCTAssertEqual(got, [b])
    }

    func test_appExtensionDependencies() {
        XCTFail()
    }

    func test_resourceBundleDependencies_returns_an_empty_list_when_a_dependency_can_host_resources() {
        // Given
        // App -> WatchApp -> Bundle
        let project = Project.test()
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .iOS, product: .watch2App)
        let bundle = Target.test(name: "Bundle", platform: .iOS, product: .bundle)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: watchApp.name, path: project.path)]),
            .target(name: watchApp.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             watchApp.name: watchApp,
                                                             bundle.name: bundle]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_resourceBundleDependencies() {
        // Given
        // App -> StaticLibrary -> Bundle
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: staticLibrary.name, path: project.path)]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             staticLibrary.name: staticLibrary,
                                                             bundle.name: bundle]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got, [bundle])
    }

    func test_resourceBundleDependencies_when_the_target_doesnt_support_resources() {
        // Given
        // StaticLibrary -> Bundle
        let project = Project.test()
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [staticLibrary.name: staticLibrary,
                                                             bundle.name: bundle]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: staticLibrary.name)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_target() {
        // Given
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app]],
                                    dependencies: [.target(name: app.name, path: project.path): Set()])
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.target(from: .target(name: app.name, path: project.path))

        // Then
        XCTAssertEqual(got, app)
    }

    func test_allDependencies() {
        // Given
        // App -> StaticLibrary -> Bundle
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: staticLibrary.name, path: project.path)]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             staticLibrary.name: staticLibrary,
                                                             bundle.name: bundle]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.allDependencies(path: project.path)

        // Then
        XCTAssertEqual(Set(got), Set([
            .target(name: bundle.name, path: project.path),
            .target(name: staticLibrary.name, path: project.path),
        ]))
    }

    func test_filterDependencies_skips_branches() {
        // Given
        // App -> StaticLibrary -> Bundle
        //     |
        //      -> FrameworkA -> FrameworkC
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: staticLibrary.name, path: project.path),
                                                              .target(name: frameworkA.name, path: project.path)]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
            .target(name: frameworkB.name, path: project.path): Set([]),
            .target(name: frameworkA.name, path: project.path): Set([.target(name: frameworkB.name, path: project.path)]),
        ]

        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             staticLibrary.name: staticLibrary,
                                                             bundle.name: bundle,
                                                             frameworkA.name: frameworkA,
                                                             frameworkB.name: frameworkB]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.filterDependencies(from: .target(name: app.name, path: project.path),
                                             test: { _ in true },
                                             skip: {
                                                 if case let ValueGraphDependency.target(name, _) = $0, name == "FrameworkA" {
                                                     return true
                                                 } else {
                                                     return false
                                                 }
                                             })

        // Then
        XCTAssertEqual(Set(got), Set([
            .target(name: bundle.name, path: project.path),
            .target(name: staticLibrary.name, path: project.path),
            .target(name: frameworkA.name, path: project.path),
        ]))
    }
}
