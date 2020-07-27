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

    func test_resourceBundleDependencies_fromTargetDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let app = Target.test(name: "App", product: .bundle)
        let project = Project.test(path: "/path/a")

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             bundle.name: bundle]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.resourceBundleDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.name), [
            "Bundle1",
        ])
    }

    func test_resourceBundleDependencies_fromProjectDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: projectB.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(name: bundle.name, path: projectA.path): Set([]),
        ]
        let graph = ValueGraph.test(path: .root,
                                    projects: [projectA.path: projectA,
                                               projectB.path: projectB],
                                    targets: [projectA.path: [bundle.name: bundle],
                                              projectB.path: [app.name: app]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.resourceBundleDependencies(path: projectB.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.name), [
            "Bundle1",
        ])
    }

    func test_resourceBundleDependencies_transitivelyViaSingleStaticFramework() {
        // Given
        let bundle = Target.test(name: "ResourceBundle", product: .bundle)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let projectA = Project.test(path: "/path/a", targets: [staticFramework, bundle])

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b", targets: [app])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: staticFramework.name, path: projectA.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(name: bundle.name, path: projectA.path): Set([]),
            .target(name: app.name, path: projectB.path): Set([.target(name: staticFramework.name, path: projectA.path)]),
        ]
        let graph = ValueGraph.test(path: .root,
                                    projects: [projectA.path: projectA,
                                               projectB.path: projectB],
                                    targets: [projectA.path: [bundle.name: bundle,
                                                              staticFramework.name: staticFramework],
                                              projectB.path: [app.name: app]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.resourceBundleDependencies(path: projectB.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.name), [
            "ResourceBundle",
        ])
    }

    func test_resourceBundleDependencies_transitivelyViaMultipleStaticFrameworks() {
        // Given
        let bundle1 = Target.test(name: "ResourceBundle1", product: .bundle)
        let bundle2 = Target.test(name: "ResourceBundle2", product: .bundle)
        let staticFramework1 = Target.test(name: "StaticFramework1", product: .staticFramework)
        let staticFramework2 = Target.test(name: "StaticFramework2", product: .staticFramework)
        let projectA = Project.test(path: "/path/a", targets: [staticFramework1, staticFramework2, bundle1, bundle2])

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b", targets: [app])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle1.name, path: projectA.path): Set([]),
            .target(name: bundle2.name, path: projectA.path): Set([]),
            .target(name: staticFramework1.name, path: projectA.path): Set([.target(name: bundle1.name, path: projectA.path),
                                                                            .target(name: staticFramework2.name, path: projectA.path)]),
            .target(name: staticFramework2.name, path: projectA.path): Set([.target(name: bundle2.name, path: projectA.path)]),
            .target(name: app.name, path: projectB.path): Set([.target(name: staticFramework1.name, path: projectA.path)]),
        ]
        let graph = ValueGraph.test(path: .root,
                                    projects: [projectA.path: projectA,
                                               projectB.path: projectB],
                                    targets: [projectA.path: [bundle1.name: bundle1,
                                                              bundle2.name: bundle2,
                                                              staticFramework1.name: staticFramework1,
                                                              staticFramework2.name: staticFramework2],
                                              projectB.path: [app.name: app]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.resourceBundleDependencies(path: projectB.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.name), [
            "ResourceBundle1",
            "ResourceBundle2",
        ])
    }

    func test_resourceBundleDependencies_transitivelyToDynamicFramework() {
        // Given
        // App -> Dynamic Framework ----
        //                              |--> Static Framework 2 -> Bundle
        // Static Framework 1 ----------
        //
        let bundle = Target.test(name: "ResourceBundle", product: .bundle)
        let staticFramework1 = Target.test(name: "StaticFramework1", product: .staticFramework)
        let staticFramework2 = Target.test(name: "StaticFramework2", product: .staticFramework)
        let dynamicFramework = Target.test(name: "DynamicFramework", product: .framework)
        let projectA = Project.test(path: "/path/a", targets: [dynamicFramework, staticFramework1, staticFramework2, bundle])
        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b", targets: [app])

        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle.name, path: projectA.path): Set([]),
            .target(name: staticFramework1.name, path: projectA.path): Set([.target(name: staticFramework2.name, path: projectA.path)]),
            .target(name: staticFramework2.name, path: projectA.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(name: dynamicFramework.name, path: projectA.path): Set([.target(name: staticFramework2.name, path: projectA.path)]),
            .target(name: app.name, path: projectB.path): Set([.target(name: dynamicFramework.name, path: projectA.path)]),
        ]
        let graph = ValueGraph.test(path: .root,
                                    projects: [projectA.path: projectA,
                                               projectB.path: projectB],
                                    targets: [projectA.path: [bundle.name: bundle,
                                                              staticFramework1.name: staticFramework1,
                                                              staticFramework2.name: staticFramework2,
                                                              dynamicFramework.name: dynamicFramework],
                                              projectB.path: [app.name: app]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let appResults = subject.resourceBundleDependencies(path: projectB.path, name: app.name)
        let dynamicFrameworkResults = subject.resourceBundleDependencies(path: projectA.path, name: dynamicFramework.name)
        let staticFramework1Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework1.name)
        let staticFramework2Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework2.name)

        // Then
        XCTAssertEqual(appResults.map(\.name), [])
        XCTAssertEqual(dynamicFrameworkResults.map(\.name), [
            "ResourceBundle",
        ])
        XCTAssertEqual(staticFramework1Results.map(\.name), [])
        XCTAssertEqual(staticFramework2Results.map(\.name), [])
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

    func test_appExtensionDependencies_when_dependencyIsAppExtension() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "AppExtension", product: .appExtension)
        let project = Project.test(targets: [target])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set([.target(name: dependency.name, path: project.path)]),
            .target(name: dependency.name, path: project.path): Set([]),
        ]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [target.name: target,
                                                             dependency.name: dependency]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.appExtensionDependencies(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(got.first?.name, "AppExtension")
    }

    func test_appExtensionDependencies_when_dependencyIsStickerPackExtension() throws {
        // When
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let project = Project.test(targets: [target])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set([.target(name: dependency.name, path: project.path)]),
            .target(name: dependency.name, path: project.path): Set([]),
        ]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [target.name: target,
                                                             dependency.name: dependency]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // Given
        let got = subject.appExtensionDependencies(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(got.first?.name, "StickerPackExtension")
    }

    func test_appExtensionDependencies_when_dependencyIsMessageExtension() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let messageExtension = Target.test(name: "MessageExtension", product: .messagesExtension)
        let project = Project.test(targets: [app, messageExtension])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: messageExtension.name, path: project.path)]),
            .target(name: messageExtension.name, path: project.path): Set([]),
        ]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: [project.path: [app.name: app,
                                                             messageExtension.name: messageExtension]],
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let result = subject.appExtensionDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.name), [
            "MessageExtension",
        ])
    }
}
