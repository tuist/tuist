import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphTraverserTests: TuistUnitTestCase {
    func test_target() {
        // Given
        let path = AbsolutePath.root
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path)

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: path,
                                         projects: [path: project],
                                         targets: [
                                             "/": ["App": app, "Framework": framework],
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Value Graph
        let frameworkNode = TargetNode.test(project: project, target: framework)
        let appNode = TargetNode.test(project: project, target: app)
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [appNode, frameworkNode],
                               targets: [project.path: [appNode, frameworkNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.target(path: "/", name: "App")
        let gotGraph = graphTraverser.target(path: "/", name: "App")

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target), app)
    }

    func test_targets() {
        // Given
        let path = AbsolutePath.root
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path)
        let framework = Target.test(name: "Framework", product: .framework)

        // When: Value Graph
        let valueGraph = ValueGraph.test(path: path,
                                         projects: [path: project],
                                         targets: [
                                             path: ["App": app, "Framework": framework],
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When: Graph
        let frameworkNode = TargetNode.test(project: project, target: framework)
        let appNode = TargetNode.test(project: project, target: app)
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [appNode, frameworkNode],
                               targets: [project.path: [appNode, frameworkNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let gotGraph = graphTraverser.targets(at: path).sorted()
        let got = subject.targets(at: path).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target), [app, framework])
    }

    func test_testTargetsDependingOn() {
        // Given
        let path = AbsolutePath.root
        let project = Project.test(path: path)
        let framework = Target.test(name: "Framework", product: .framework)
        let dependantFramework = Target.test(name: "DependantFramework", product: .framework)
        let unitTests = Target.test(name: "UnitTests", product: .unitTests)
        let uiTests = Target.test(name: "UITests", product: .uiTests)
        let targets: [AbsolutePath: [String: Target]] = [
            path: [framework.name: framework,
                   dependantFramework.name: dependantFramework,
                   unitTests.name: unitTests,
                   uiTests.name: uiTests],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: unitTests.name, path: path): Set([.target(name: framework.name, path: path)]),
            .target(name: uiTests.name, path: path): Set([.target(name: framework.name, path: path)]),
            .target(name: dependantFramework.name, path: path): Set([.target(name: framework.name, path: path)]),
        ]

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: path,
                                         projects: [path: project],
                                         targets: targets,
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let frameworkNode = TargetNode.test(project: project, target: framework)
        let dependantFrameworkNode = TargetNode.test(project: project, target: dependantFramework, dependencies: [frameworkNode])
        let unitTestsNode = TargetNode.test(project: project, target: unitTests, dependencies: [frameworkNode])
        let uiTestsNode = TargetNode.test(project: project, target: uiTests, dependencies: [frameworkNode])

        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [frameworkNode, dependantFrameworkNode, unitTestsNode, uiTestsNode],
                               targets: [project.path: [frameworkNode, dependantFrameworkNode, unitTestsNode, uiTestsNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let gotGraph = graphTraverser.testTargetsDependingOn(path: path, name: framework.name).sorted()
        let got = subject.testTargetsDependingOn(path: path, name: framework.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.map(\.target), [uiTests, unitTests])
    }

    func test_directStaticDependencies() {
        // Given
        let path = AbsolutePath.root
        let project = Project.test(path: path)
        let framework = Target.test(name: "Framework", product: .framework)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let targets: [AbsolutePath: [String: Target]] = [
            path: [framework.name: framework,
                   staticLibrary.name: staticLibrary],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: framework.name, path: path): Set([.target(name: staticLibrary.name, path: path)]),
        ]

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: path,
                                         targets: targets,
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let staticLibraryNode = TargetNode.test(project: project, target: staticLibrary)
        let frameworkNode = TargetNode.test(project: project, target: framework, dependencies: [staticLibraryNode])

        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [frameworkNode, staticLibraryNode],
                               targets: [project.path: [frameworkNode, staticLibraryNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.directStaticDependencies(path: path, name: framework.name).sorted()
        let gotGraph = graphTraverser.directStaticDependencies(path: path, name: framework.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got, [.product(target: staticLibrary.name, productName: staticLibrary.productNameWithExtension)])
    }

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
        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: targets,
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let cNode = TargetNode.test(project: project, target: b)
        let bNode = TargetNode.test(project: project, target: b, dependencies: [cNode])
        let aNode = TargetNode.test(project: project, target: a, dependencies: [bNode])

        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [aNode, bNode, cNode],
                               targets: [project.path: [aNode, bNode, cNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.directTargetDependencies(path: project.path, name: a.name).sorted()
        let gotGraph = graphTraverser.directTargetDependencies(path: project.path, name: a.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.map(\.target), [b])
    }

    func test_directTargetDependencies_returnsLocalProjectTargetsOnly() {
        // Given
        // Project A: A1 -> A2
        //               -> (Project B) B1
        // Project B: B1
        let projectA = Project.test(path: "/ProjectA", name: "ProjectA")
        let projectB = Project.test(path: "/ProjectB", name: "ProjectB")
        let a1 = Target.test(name: "A1")
        let a2 = Target.test(name: "A2")
        let b1 = Target.test(name: "B1")
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: a1.name, path: projectA.path): Set([
                .target(name: a2.name, path: projectA.path),
                .target(name: b1.name, path: projectB.path),
            ]),
        ]
        let targets: [AbsolutePath: [String: Target]] = [
            projectA.path: [
                a1.name: a1,
                a2.name: a2,
            ],
            projectB.path: [
                b1.name: b1,
            ],
        ]
        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: projectA.path,
                                         projects: [projectA.path: projectA, projectB.path: projectB],
                                         targets: targets,
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let b1Node = TargetNode.test(project: projectB, target: b1)
        let a2Node = TargetNode.test(project: projectA, target: a2)
        let a1Node = TargetNode.test(project: projectA, target: a1, dependencies: [a2Node, b1Node])

        let graph = Graph.test(entryPath: projectA.path,
                               entryNodes: [a1Node, a2Node, b1Node],
                               targets: [
                                   projectA.path: [a1Node, a2Node],
                                   projectB.path: [b1Node],
                               ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.directTargetDependencies(path: projectA.path, name: a1.name).sorted()
        let gotGraph = graphTraverser.directTargetDependencies(path: projectA.path, name: a1.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.map(\.target), [a2])
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  watchApp.name: watchApp,
                                                                  bundle.name: bundle]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let bundleNode = TargetNode.test(project: project, target: bundle)
        let watchAppNode = TargetNode.test(project: project, target: watchApp, dependencies: [bundleNode])
        let appNode = TargetNode.test(project: project, target: app, dependencies: [watchAppNode])

        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [appNode, bundleNode, watchAppNode],
                               targets: [project.path: [appNode, bundleNode, watchAppNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = graphTraverser.resourceBundleDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticLibrary.name: staticLibrary,
                                                                  bundle.name: bundle]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let bundleNode = TargetNode.test(project: project, target: bundle)
        let staticLibraryNode = TargetNode.test(project: project, target: staticLibrary, dependencies: [bundleNode])
        let appNode = TargetNode.test(project: project, target: app, dependencies: [staticLibraryNode])
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [appNode, bundleNode, staticLibraryNode],
                               targets: [project.path: [appNode, bundleNode, staticLibraryNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = graphTraverser.resourceBundleDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.map(\.target), [bundle])
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [staticLibrary.name: staticLibrary,
                                                                  bundle.name: bundle]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let bundleNode = TargetNode.test(project: project, target: bundle)
        let staticLibraryNode = TargetNode.test(project: project, target: staticLibrary, dependencies: [bundleNode])
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [bundleNode, staticLibraryNode],
                               targets: [project.path: [bundleNode, staticLibraryNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: staticLibrary.name).sorted()
        let gotGraph = graphTraverser.resourceBundleDependencies(path: project.path, name: staticLibrary.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
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

        // Given: Value graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  bundle.name: bundle]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: app, dependencies: [bundle]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let gotGraph = graphTraverser.resourceBundleDependencies(path: project.path, name: app.name).sorted()
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target.name), [
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: .root,
                                         projects: [projectA.path: projectA,
                                                    projectB.path: projectB],
                                         targets: [projectA.path: [bundle.name: bundle],
                                                   projectB.path: [app.name: app]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectA, target: bundle, dependencies: []),
                                     (project: projectB, target: app, dependencies: [bundle]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let graphGot = graphTraverser.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(graphGot, got)
        XCTAssertEqual(got.map(\.target.name), [
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: .root,
                                         projects: [projectA.path: projectA,
                                                    projectB.path: projectB],
                                         targets: [projectA.path: [bundle.name: bundle,
                                                                   staticFramework.name: staticFramework],
                                                   projectB.path: [app.name: app]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectB, target: app, dependencies: [staticFramework]),
                                     (project: projectA, target: staticFramework, dependencies: [bundle]),
                                     (project: projectA, target: bundle, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let gotGraph = graphTraverser.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target.name), [
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: .root,
                                         projects: [projectA.path: projectA,
                                                    projectB.path: projectB],
                                         targets: [projectA.path: [bundle1.name: bundle1,
                                                                   bundle2.name: bundle2,
                                                                   staticFramework1.name: staticFramework1,
                                                                   staticFramework2.name: staticFramework2],
                                                   projectB.path: [app.name: app]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectB, target: app, dependencies: [staticFramework1]),
                                     (project: projectA, target: staticFramework1, dependencies: [staticFramework2, bundle1]),
                                     (project: projectA, target: staticFramework2, dependencies: [bundle2]),
                                     (project: projectA, target: bundle1, dependencies: []),
                                     (project: projectA, target: bundle2, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let gotGraph = graphTraverser.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target.name), [
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: .root,
                                         projects: [projectA.path: projectA,
                                                    projectB.path: projectB],
                                         targets: [projectA.path: [bundle.name: bundle,
                                                                   staticFramework1.name: staticFramework1,
                                                                   staticFramework2.name: staticFramework2,
                                                                   dynamicFramework.name: dynamicFramework],
                                                   projectB.path: [app.name: app]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectA, target: bundle, dependencies: []),
                                     (project: projectA, target: staticFramework1, dependencies: [staticFramework2]),
                                     (project: projectA, target: staticFramework2, dependencies: [bundle]),
                                     (project: projectA, target: dynamicFramework, dependencies: [staticFramework2]),
                                     (project: projectB, target: app, dependencies: [dynamicFramework]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let appResults = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let dynamicFrameworkResults = subject.resourceBundleDependencies(path: projectA.path, name: dynamicFramework.name).sorted()
        let staticFramework1Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework1.name).sorted()
        let staticFramework2Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework2.name).sorted()

        let appResultsGraph = graphTraverser.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let dynamicFrameworkResultsGraph = graphTraverser.resourceBundleDependencies(path: projectA.path, name: dynamicFramework.name).sorted()
        let staticFramework1ResultsGraph = graphTraverser.resourceBundleDependencies(path: projectA.path, name: staticFramework1.name).sorted()
        let staticFramework2ResultsGraph = graphTraverser.resourceBundleDependencies(path: projectA.path, name: staticFramework2.name).sorted()

        // Then
        XCTAssertEqual(appResults, appResultsGraph)
        XCTAssertEqual(dynamicFrameworkResults, dynamicFrameworkResultsGraph)
        XCTAssertEqual(staticFramework1Results, staticFramework1ResultsGraph)
        XCTAssertEqual(staticFramework2Results, staticFramework2ResultsGraph)

        XCTAssertEqual(appResults.map(\.target.name), [])
        XCTAssertEqual(dynamicFrameworkResults.map(\.target.name), [
            "ResourceBundle",
        ])
        XCTAssertEqual(staticFramework1Results.map(\.target.name), [])
        XCTAssertEqual(staticFramework2Results.map(\.target.name), [])
    }

    func test_target_from_dependency() {
        // Given
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app]],
                                         dependencies: [.target(name: app.name, path: project.path): Set()])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(projects: [project],
                                 dependencies: [
                                     (project: project, target: app, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.target(path: project.path, name: app.name)
        let gotGraph = graphTraverser.target(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got?.target, app)
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticLibrary.name: staticLibrary,
                                                                  bundle.name: bundle]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target,
                                                                  dependency.name: dependency]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.appExtensionDependencies(path: project.path, name: target.name).sorted()
        let gotGraph = graphTraverser.appExtensionDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.first?.target.name, "AppExtension")
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

        // Given: Value graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target,
                                                                  dependency.name: dependency]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given
        let got = subject.appExtensionDependencies(path: project.path, name: target.name).sorted()
        let gotGraph = graphTraverser.appExtensionDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.first?.target.name, "StickerPackExtension")
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

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  messageExtension.name: messageExtension]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [messageExtension]),
                                     (target: messageExtension, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.appExtensionDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = graphTraverser.appExtensionDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.map(\.target.name), [
            "MessageExtension",
        ])
    }

    func test_appClipDependencies() throws {
        // Given
        let project = Project.test()
        let app = Target.test(name: "app", product: .app)
        let appClip = Target.test(name: "clip", product: .appClip)

        // Given: Value graph
        let appClipNode = TargetNode.test(project: project,
                                          target: appClip)
        let appNode = TargetNode.test(project: project,
                                      target: app,
                                      dependencies: [appClipNode])
        let graph = Graph.test(entryNodes: [appNode, appClipNode],
                               projects: [project],
                               targets: [project.path: [appNode, appClipNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app, appClip.name: appClip]],
                                         dependencies: [.target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: appClip.name, path: project.path))])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let graphGot = graphTraverser.appClipDependencies(path: project.path, name: app.name)
        let got = subject.appClipDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(graphGot, got)
        XCTAssertEqual(got, .init(path: project.path, target: appClip, project: project))
    }

    func test_embeddableFrameworks_when_targetIsNotApp() throws {
        // Given
        let target = Target.test(name: "Main", product: .framework)
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Graph
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [targetNode, dependencyNode],
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [dependency.name: dependency, target.name: target]],
                                         dependencies: [
                                             .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertNil(got.first)
    }

    func test_embeddableFrameworks_when_dependencyIsATarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Graph
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project],
                               targets: [project.path: [targetNode, dependencyNode]])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [dependency.name: dependency, target.name: target]],
                                         dependencies: [
                                             .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()
        let gotGraph = graph.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.first, GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework"))
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        // Given
        let frameworkPath = AbsolutePath("/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
        let frameworkNode = FrameworkNode.test(path: frameworkPath,
                                               dsymPath: nil,
                                               bcsymbolmapPaths: [],
                                               linking: .dynamic,
                                               architectures: [.arm64],
                                               dependencies: [])
        let project = Project.test(targets: [target])

        // Given: Graph
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [frameworkNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [frameworkNode],
                               targets: [project.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let frameworkDependency = ValueGraphDependency.testFramework(path: frameworkPath,
                                                                     binaryPath: frameworkPath.appending(component: "test"),
                                                                     dsymPath: nil,
                                                                     bcsymbolmapPaths: [],
                                                                     linking: .dynamic,
                                                                     architectures: [.arm64],
                                                                     isCarthage: false)
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [
                                             .target(name: target.name, path: project.path): Set(arrayLiteral: frameworkDependency),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: target.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertEqual(got.first, GraphDependencyReference(precompiledNode: frameworkNode))
    }

    func test_embeddableFrameworks_when_transitiveXCFrameworks() throws {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let project = Project.test(targets: [app])

        // Given: Graph
        let dNode = XCFrameworkNode.test(path: "/xcframeworks/d.xcframework",
                                         infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
                                         primaryBinaryPath: "/xcframeworks/d.xcframework/d",
                                         linking: .dynamic)
        let cNode = XCFrameworkNode.test(path: "/xcframeworks/c.xcframework",
                                         infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
                                         primaryBinaryPath: "/xcframeworks/c.xcframework/c",
                                         linking: .dynamic,
                                         dependencies: [.xcframework(dNode)])
        let appNode = TargetNode.test(target: app, dependencies: [cNode])

        let cache = GraphLoaderCache()
        cache.add(targetNode: appNode)
        cache.add(precompiledNode: dNode)
        cache.add(precompiledNode: cNode)
        let graph = Graph.test(entryNodes: [appNode],
                               projects: [project],
                               precompiled: [cNode, dNode],
                               targets: [project.path: [appNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let cDependency = ValueGraphDependency.xcframework(path: "/xcframeworks/c.xcframework",
                                                           infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
                                                           primaryBinaryPath: "/xcframeworks/c.xcframework/c",
                                                           linking: .dynamic)
        let dDependency = ValueGraphDependency.xcframework(path: "/xcframeworks/d.xcframework",
                                                           infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
                                                           primaryBinaryPath: "/xcframeworks/d.xcframework/d",
                                                           linking: .dynamic)
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: cDependency),
            cDependency: Set(arrayLiteral: dDependency),
            dDependency: Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: app.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
            GraphDependencyReference(precompiledNode: cNode),
            GraphDependencyReference(precompiledNode: dNode),
        ])
    }

    func test_embeddableFrameworks_when_dependencyIsATransitiveFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Graph
        let frameworkNode = FrameworkNode.test(path: "/framework.framework",
                                               dsymPath: nil,
                                               bcsymbolmapPaths: [],
                                               linking: .dynamic,
                                               architectures: [.arm64],
                                               dependencies: [])
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
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(name: dependency.name, path: project.path): Set(arrayLiteral: .testFramework(path: "/framework.framework",
                                                                                                 binaryPath: "/framework.framework/framework",
                                                                                                 dsymPath: nil,
                                                                                                 bcsymbolmapPaths: [],
                                                                                                 linking: .dynamic,
                                                                                                 architectures: [.arm64],
                                                                                                 isCarthage: false)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target, dependency.name: dependency]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: target.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
            GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework"),
            GraphDependencyReference(precompiledNode: frameworkNode),
        ])
    }

    func test_embeddableFrameworks_when_precompiledStaticFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        let frameworkNode = FrameworkNode.test(path: "/test/StaticFramework.framework",
                                               dsymPath: nil,
                                               bcsymbolmapPaths: [],
                                               linking: .static,
                                               architectures: [.arm64],
                                               dependencies: [])
        let targetNode = TargetNode(
            project: project,
            target: target,
            dependencies: [frameworkNode]
        )

        // Given: Graph
        let graph = Graph.test(projects: [project],
                               precompiled: [frameworkNode],
                               targets: [project.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .testFramework(path: "/test/StaticFramework.framework",
                                                                                             binaryPath: "/test/StaticFramework.framework/StaticFramework",
                                                                                             dsymPath: nil,
                                                                                             bcsymbolmapPaths: [],
                                                                                             linking: .static,
                                                                                             architectures: [.arm64],
                                                                                             isCarthage: false)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: target.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertTrue(gotGraph.isEmpty)
    }

    func test_embeddableFrameworks_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchExtension.name, path: project.path): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
            .target(name: frameworkA.name, path: project.path): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [frameworkA.name: frameworkA,
                                                                  frameworkB.name: frameworkB,
                                                                  watchExtension.name: watchExtension]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: watchExtension.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework"),
            .product(target: "FrameworkB", productName: "FrameworkB.framework"),
        ])
    }

    func test_embeddableDependencies_whenHostedTestTarget() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  tests.name: tests,
                                                                  framework.name: framework]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: tests.name).sorted()
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_when_nonHostedTestTarget_dynamic_dependencies() throws {
        // Given
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")
        let target = Target.test(name: "LocallyBuiltFramework", product: .framework)

        // Given: Graph
        let precompiledNode = FrameworkNode.test(path: "/test/test.framework",
                                                 dsymPath: nil,
                                                 bcsymbolmapPaths: [],
                                                 linking: .dynamic,
                                                 architectures: [.arm64],
                                                 dependencies: [])

        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [])

        let unitTestsNode = TargetNode(project: project, target: unitTests, dependencies: [precompiledNode, targetNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(targetNode: unitTestsNode)

        let graph = Graph(
            name: "Graph",
            entryPath: project.path,
            cache: cache,
            entryNodes: [unitTestsNode],
            workspace: Workspace.test()
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testFramework(path: "/test/test.framework",
                                                                       binaryPath: "/test/test.framework/test",
                                                                       dsymPath: nil,
                                                                       bcsymbolmapPaths: [],
                                                                       linking: .dynamic,
                                                                       architectures: [.arm64],
                                                                       isCarthage: false)
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(),
            .target(name: unitTests.name, path: project.path): Set(arrayLiteral: .target(name: target.name, path: project.path), precompiledDependency),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [unitTests.name: unitTests,
                                                                  target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: unitTests.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_whenHostedTestTarget_transitiveDepndencies() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let staticFramework = Target.test(name: "StaticFramework",
                                          product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: framework, dependencies: []),
                                     (target: staticFramework, dependencies: [framework]),
                                     (target: tests, dependencies: [app, staticFramework]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path), .target(name: staticFramework.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [framework.name: framework,
                                                                  staticFramework.name: staticFramework,
                                                                  app.name: app,
                                                                  tests.name: tests]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: tests.name).sorted()
        let got = subject.embeddableFrameworks(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(gotGraph, got)
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_whenUITest_andAppPrecompiledDepndencies() throws {
        // Given

        let app = Target.test(name: "App", product: .app)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let precompiledNode = FrameworkNode.test(path: "/test/test.framework",
                                                 dsymPath: nil,
                                                 bcsymbolmapPaths: [],
                                                 linking: .dynamic,
                                                 architectures: [.arm64],
                                                 dependencies: [])
        let appNode = TargetNode(project: project, target: app, dependencies: [precompiledNode])
        let uiTestsNode = TargetNode(project: project, target: uiTests, dependencies: [appNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(targetNode: appNode)
        cache.add(targetNode: uiTestsNode)

        let graph = Graph(
            name: "Graph",
            entryPath: project.path,
            cache: cache,
            entryNodes: [appNode, uiTestsNode],
            workspace: Workspace.test()
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testFramework(path: "/test/test.framework",
                                                                       binaryPath: "/test/test.framework/test",
                                                                       dsymPath: nil,
                                                                       bcsymbolmapPaths: [],
                                                                       linking: .dynamic,
                                                                       architectures: [.arm64],
                                                                       isCarthage: false)
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: precompiledDependency),
            .target(name: uiTests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
            precompiledDependency: Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  uiTests.name: uiTests]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: uiTests.name).sorted()
        let gotGraph = graphTraverser.embeddableFrameworks(path: project.path, name: uiTests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertTrue(gotGraph.isEmpty)
    }

    func test_librariesPublicHeadersFolders() throws {
        // Given
        let target = Target.test(name: "Main")
        let publicHeadersPath = AbsolutePath("/test/public/")
        let project = Project.test(targets: [target])

        // Given: Graph
        let precompiledNode = LibraryNode.test(path: AbsolutePath("/test/test.a"),
                                               publicHeaders: publicHeadersPath,
                                               linking: .static)
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNode],
                               targets: [project.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testLibrary(path: AbsolutePath("/test/test.a"),
                                                                     publicHeaders: publicHeadersPath,
                                                                     linking: .static,
                                                                     architectures: [])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.librariesPublicHeadersFolders(path: project.path,
                                                        name: target.name).sorted()
        let gotGraph = graphTraverser.librariesPublicHeadersFolders(path: project.path,
                                                                    name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.first, publicHeadersPath)
    }

    func test_librariesSearchPaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Graph
        let precompiledNode = LibraryNode.test(path: "/test/test.a",
                                               publicHeaders: "/test/public/",
                                               architectures: [],
                                               linking: .static)
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNode],
                               targets: [project.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testLibrary(path: "/test/test.a",
                                                                     publicHeaders: "/test/public/",
                                                                     linking: .static,
                                                                     architectures: [])
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.librariesSearchPaths(path: project.path, name: target.name).sorted()
        let gotGraph = graphTraverser.librariesSearchPaths(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [AbsolutePath("/test")])
    }

    func test_linkableDependencies_whenPrecompiled() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Graph
        let precompiledNode = FrameworkNode.test(path: "/test/test.framework",
                                                 dsymPath: nil,
                                                 bcsymbolmapPaths: [],
                                                 linking: .dynamic,
                                                 architectures: [.arm64])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let graph = Graph.test(targets: [targetNode.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testFramework(path: "/test/test.framework",
                                                                       binaryPath: "/test/test.framework/test",
                                                                       dsymPath: nil,
                                                                       bcsymbolmapPaths: [],
                                                                       linking: .dynamic,
                                                                       architectures: [.arm64],
                                                                       isCarthage: false)
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(gotGraph.first, GraphDependencyReference(precompiledNode: precompiledNode))
    }

    func test_linkableDependencies_whenALibraryTarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        // Given: Graph
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let graph = Graph.test(projects: [project], targets: [
            project.path: [dependencyNode, targetNode],
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(name: dependency.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target, dependency.name: dependency]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.first, .product(target: "Dependency", productName: "libDependency.a"))
    }

    func test_linkableDependencies_whenAFrameworkTarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        // Given: Graph
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
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(name: dependency.name, path: project.path): Set(arrayLiteral: .target(name: staticDependency.name, path: project.path)),
            .target(name: staticDependency.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target,
                                                                  dependency.name: dependency,
                                                                  staticDependency.name: staticDependency]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path,
                                                   name: target.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path,
                                                               name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)

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
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: [dynamicFramework]),
                                     (target: dynamicFramework, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework.name, path: project.path)),
            .target(name: dynamicFramework.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticFramework.name: staticFramework,
                                                                  dynamicFramework.name: dynamicFramework]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [GraphDependencyReference.product(target: "DynamicFramework", productName: "DynamicFramework.framework"),
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
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework1]),
                                     (target: dynamicFramework1, dependencies: [staticFramework1]),
                                     (target: staticFramework1, dependencies: [staticFramework2]),
                                     (target: staticFramework2, dependencies: [dynamicFramework2]),
                                     (target: dynamicFramework2, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework1.name, path: project.path)),
            .target(name: dynamicFramework1.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework1.name, path: project.path)),
            .target(name: staticFramework1.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework2.name, path: project.path)),
            .target(name: staticFramework2.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework2.name, path: project.path)),
            .target(name: dynamicFramework2.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  dynamicFramework1.name: dynamicFramework1,
                                                                  dynamicFramework2.name: dynamicFramework2,
                                                                  staticFramework1.name: staticFramework1,
                                                                  staticFramework2.name: staticFramework2]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let appGot = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicFramework1Got = try subject.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()
        let appGotGraph = try graphTraverser.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicFramework1GotGraph = try graphTraverser.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()

        // Then
        XCTAssertEqual(appGot, appGotGraph)
        XCTAssertEqual(dynamicFramework1Got, dynamicFramework1GotGraph)

        XCTAssertEqual(appGot, [
            GraphDependencyReference.product(target: "DynamicFramework1", productName: "DynamicFramework1.framework"),
        ])
        XCTAssertEqual(dynamicFramework1Got, [
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

        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework1]),
                                     (target: dynamicFramework1, dependencies: [dynamicFramework2]),
                                     (target: dynamicFramework2, dependencies: [staticFramework1]),
                                     (target: staticFramework1, dependencies: [staticFramework2]),
                                     (target: staticFramework2, dependencies: [dynamicFramework3]),
                                     (target: dynamicFramework3, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework1.name, path: project.path)),
            .target(name: dynamicFramework1.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework2.name, path: project.path)),
            .target(name: dynamicFramework2.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework1.name, path: project.path)),
            .target(name: staticFramework1.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework2.name, path: project.path)),
            .target(name: staticFramework2.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework3.name, path: project.path)),
            .target(name: dynamicFramework3.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  dynamicFramework1.name: dynamicFramework1,
                                                                  dynamicFramework2.name: dynamicFramework2,
                                                                  staticFramework1.name: staticFramework1,
                                                                  staticFramework2.name: staticFramework2,
                                                                  dynamicFramework3.name: dynamicFramework3]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let dynamicFramework1Got = try subject.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()
        let dynamicFramework1GotGraph = try graphTraverser.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()

        // Then
        XCTAssertEqual(dynamicFramework1Got, dynamicFramework1GotGraph)
        XCTAssertEqual(dynamicFramework1Got, [GraphDependencyReference.product(target: "DynamicFramework2", productName: "DynamicFramework2.framework")])
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
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkA, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: staticFrameworkB.name, path: project.path)),
            .target(name: staticFrameworkB.name, path: project.path): Set(arrayLiteral: .target(name: staticFrameworkA.name, path: project.path)),
            .target(name: staticFrameworkA.name, path: project.path): Set(arrayLiteral: .sdk(name: "some.framework",
                                                                                             path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                                                                                             status: .optional,
                                                                                             source: .developer)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticFrameworkB.name: staticFrameworkB,
                                                                  staticFrameworkA.name: staticFrameworkA]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.compactMap(sdkDependency), [
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
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [dynamicFramework]),
                                     (target: dynamicFramework, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: dynamicFramework.name, path: project.path)),
            .target(name: dynamicFramework.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .sdk(name: "some.framework",
                                                                                            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                                                                                            status: .optional,
                                                                                            source: .developer)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticFramework.name: staticFramework,
                                                                  dynamicFramework.name: dynamicFramework]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let appGot = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicGot = try subject.linkableDependencies(path: project.path, name: dynamicFramework.name).sorted()
        let appGotGraph = try graphTraverser.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicGotGraph = try graphTraverser.linkableDependencies(path: project.path, name: dynamicFramework.name).sorted()

        // Then
        XCTAssertEqual(appGot, appGotGraph)
        XCTAssertEqual(dynamicGot, dynamicGotGraph)

        XCTAssertEqual(appGotGraph.compactMap(sdkDependency), [])
        XCTAssertEqual(dynamicGotGraph.compactMap(sdkDependency),
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

        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .sdk(name: "some.framework",
                                                                                            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                                                                                            status: .optional,
                                                                                            source: .developer)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticFramework.name: staticFramework]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.compactMap(sdkDependency), [SDKPathAndStatus(name: "some.framework", status: .optional)])
    }

    func test_linkableDependencies_transitiveSDKDependenciesImmediateDependencies() throws {
        // Given
        let staticFramework = Target.test(name: "StaticFrameworkA",
                                          product: .staticFramework,
                                          dependencies: [.sdk(name: "thingone.framework", status: .optional),
                                                         .sdk(name: "thingtwo.framework", status: .required)])

        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: staticFramework, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .sdk(name: "thingone.framework",
                                                                                            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/thingone.framework",
                                                                                            status: .optional,
                                                                                            source: .developer),
                                                                         .sdk(name: "thingtwo.framework",
                                                                              path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/thingtwo.framework",
                                                                              status: .required,
                                                                              source: .developer)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [staticFramework.name: staticFramework]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: staticFramework.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: staticFramework.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.compactMap(sdkDependency),
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

        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: staticFrameworkA.name, path: project.path): Set(arrayLiteral: .target(name: staticFrameworkB.name, path: project.path),
                                                                          .sdk(name: "ThingOne.framework",
                                                                               path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/ThingOne.framework",
                                                                               status: .optional,
                                                                               source: .developer)),
            .target(name: staticFrameworkB.name, path: project.path): Set(arrayLiteral: .sdk(name: "ThingTwo.framework",
                                                                                             path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/ThingTwo.framework",
                                                                                             status: .optional,
                                                                                             source: .developer)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [staticFrameworkA.name: staticFrameworkA,
                                                                  staticFrameworkB.name: staticFrameworkB]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: staticFrameworkA.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: staticFrameworkA.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got.compactMap(sdkDependency),
                       [SDKPathAndStatus(name: "ThingOne.framework", status: .optional)])
    }

    func test_linkableDependencies_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchExtension.name, path: project.path): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(name: frameworkA.name, path: project.path): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [watchExtension.name: watchExtension,
                                                                  frameworkA.name: frameworkA,
                                                                  frameworkB.name: frameworkB]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: watchExtension.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework"),
        ])
    }

    func test_linkableDependencies_when_watchExtension_staticDependency() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .staticFramework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchExtension, dependencies: [frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchExtension.name, path: project.path): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(name: frameworkA.name, path: project.path): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [watchExtension.name: watchExtension,
                                                                  frameworkA.name: frameworkA,
                                                                  frameworkB.name: frameworkB]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: watchExtension.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
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
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                     (target: tests, dependencies: [app, staticFramework]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path),
                                                               .target(name: app.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  staticFramework.name: staticFramework,
                                                                  tests.name: tests]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertTrue(got.isEmpty)
    }

    func test_linkableDependencies_whenHostedTestTarget_withCommonDynamicProducts() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app, framework]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path),
                                                               .target(name: app.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  framework.name: framework,
                                                                  tests.name: tests]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [
            .product(target: "Framework", productName: "Framework.framework"),
        ])
    }

    func test_linkableDependencies_whenHostedTestTarget_doNotIncludeRedundantDependencies() throws {
        // Given
        let framework = Target.test(name: "Framework",
                                    product: .framework)

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [framework]),
                                     (target: framework, dependencies: []),
                                     (target: tests, dependencies: [app]),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  framework.name: framework,
                                                                  tests.name: tests]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertTrue(got.isEmpty)
    }

    func test_linkableDependencies_when_appClipSDKNode() throws {
        // Given
        let target = Target.test(name: "AppClip", product: .appClip)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [(target: target, dependencies: [])])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .sdk(name: "AppClip.framework", path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/AppClip.framework", status: .required, source: .system)),
        ]
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()
        let gotGraph = try graphTraverser.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [.sdk(path: try SDKNode.appClip(status: .required).path, status: .required, source: .system)])
    }

    func test_librariesSwiftIncludePaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNodeA = LibraryNode.test(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap")
        let precompiledNodeB = LibraryNode.test(path: "/test/another.a", swiftModuleMap: nil)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [
                                             .target(name: target.name, path: project.path): Set([
                                                 .testLibrary(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap"),
                                                 .testLibrary(path: "/test/another.b"),
                                             ]),
                                             .testLibrary(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap"): Set([]),
                                             .testLibrary(path: "/test/another.b"): Set([]),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // Given: Graph
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNodeA, precompiledNodeB])
        let graph = Graph.test(projects: [project],
                               precompiled: [precompiledNodeA, precompiledNodeB],
                               targets: [project.path: [targetNode]])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.librariesSwiftIncludePaths(path: project.path, name: target.name).sorted()
        let gotGraph = graphTraverser.librariesSwiftIncludePaths(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got, [AbsolutePath("/test/modules")])
    }

    func test_runPathSearchPaths() throws {
        // Given
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let precompiledNode = FrameworkNode.test(path: "/test/test.framework",
                                                 dsymPath: nil,
                                                 bcsymbolmapPaths: [],
                                                 linking: .dynamic,
                                                 architectures: [.arm64])
        let precompiledNodeB = FrameworkNode.test(path: "/test/testb.framework",
                                                  dsymPath: nil,
                                                  bcsymbolmapPaths: [],
                                                  linking: .dynamic,
                                                  architectures: [.arm64])
        let unitTestsNode = TargetNode(project: project, target: unitTests, dependencies: [precompiledNode, precompiledNodeB])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(precompiledNode: precompiledNode)
        cache.add(precompiledNode: precompiledNodeB)
        cache.add(targetNode: unitTestsNode)

        let graph = Graph(
            name: "Graph",
            entryPath: project.path,
            cache: cache,
            entryNodes: [unitTestsNode],
            workspace: Workspace.test(path: project.path)
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testFramework(path: "/test/test.famework",
                                                                       binaryPath: "/test/test.framework/test",
                                                                       dsymPath: nil,
                                                                       bcsymbolmapPaths: [],
                                                                       linking: .dynamic,
                                                                       architectures: [.arm64],
                                                                       isCarthage: false)
        let precompiledBDependency = ValueGraphDependency.testFramework(path: "/test/testb.famework",
                                                                        binaryPath: "/test/testb.framework/testb",
                                                                        dsymPath: nil,
                                                                        bcsymbolmapPaths: [],
                                                                        linking: .dynamic,
                                                                        architectures: [.arm64],
                                                                        isCarthage: false)
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [unitTests.name: unitTests]],
                                         dependencies: [
                                             .target(name: unitTests.name, path: project.path): Set([precompiledDependency, precompiledBDependency]),
                                             precompiledDependency: Set(),
                                             precompiledBDependency: Set(),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()
        let gotGraph = graphTraverser.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(
            got,
            [AbsolutePath("/test")]
        )
    }

    func test_runPathSearchPaths_when_unit_tests_with_hosted_target() throws {
        // Given
        let precompiledNode = FrameworkNode.test(path: "/test/test.framework",
                                                 dsymPath: nil,
                                                 bcsymbolmapPaths: [],
                                                 linking: .dynamic,
                                                 architectures: [.arm64])
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

        // Given: Graph
        let graph = Graph(
            name: "Graph",
            entryPath: project.path,
            cache: cache,
            entryNodes: [unitTestsNode],
            workspace: Workspace.test()
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let precompiledDependency = ValueGraphDependency.testFramework(path: "/test/test.famework",
                                                                       binaryPath: "/test/test.framework/test",
                                                                       dsymPath: nil,
                                                                       bcsymbolmapPaths: [],
                                                                       linking: .dynamic,
                                                                       architectures: [.arm64],
                                                                       isCarthage: false)
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [unitTests.name: unitTests,
                                                                  app.name: app]],
                                         dependencies: [
                                             .target(name: unitTests.name, path: project.path): Set([precompiledDependency, .target(name: app.name, path: project.path)]),
                                             .target(name: app.name, path: project.path): Set([]),
                                             precompiledDependency: Set(),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()
        let gotGraph = graphTraverser.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEmpty(got)
    }

    func test_hostTargetNode_watchApp() {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [watchApp]),
                                     (target: watchApp, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [app.name: app,
                                                                  watchApp.name: watchApp]],
                                         dependencies: [
                                             .target(name: app.name, path: project.path): Set([.target(name: watchApp.name, path: project.path)]),
                                             .target(name: watchApp.name, path: project.path): Set([]),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.hostTargetFor(path: project.path, name: "WatchApp")
        let gotGraph = graphTraverser.hostTargetFor(path: project.path, name: "WatchApp")

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got?.target, app)
    }

    func test_hostTargetNode_watchAppExtension() {
        // Given
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let watchAppExtension = Target.test(name: "WatchAppExtension", platform: .watchOS, product: .watch2Extension)
        let project = Project.test(path: "/path/a")

        // Given: Graph
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: watchApp, dependencies: [watchAppExtension]),
                                     (target: watchAppExtension, dependencies: []),
                                 ])
        let graphTraverser = GraphTraverser(graph: graph)

        // Given: Value Graph
        let valueGraph = ValueGraph.test(projects: [project.path: project],
                                         targets: [project.path: [watchAppExtension.name: watchAppExtension,
                                                                  watchApp.name: watchApp]],
                                         dependencies: [
                                             .target(name: watchApp.name, path: project.path): Set([.target(name: watchAppExtension.name, path: project.path)]),
                                             .target(name: watchAppExtension.name, path: project.path): Set([]),
                                         ])
        let subject = ValueGraphTraverser(graph: valueGraph)

        // When
        let got = subject.hostTargetFor(path: project.path, name: "WatchAppExtension")
        let gotGraph = graphTraverser.hostTargetFor(path: project.path, name: "WatchAppExtension")

        // Then
        XCTAssertEqual(got, gotGraph)
        XCTAssertEqual(got?.target, watchApp)
    }

    // MARK: - Helpers

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
