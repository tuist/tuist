import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class GraphTraverserTests: TuistUnitTestCase {
    func test_dependsOnXCTest_when_is_framework() {
        // Given
        let project = Project.test()
        let frameworkTarget = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "Framework",
                product: .framework
            )
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    frameworkTarget.target.name: frameworkTarget.target,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.dependsOnXCTest(path: project.path, name: "Framework")

        // Then
        XCTAssertFalse(got)
    }

    func test_dependsOnXCTest_when_is_tests_bundle() {
        // Given
        let project = Project.test()
        let unitTestsTarget = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "UnitTests",
                product: .unitTests
            )
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    unitTestsTarget.target.name: unitTestsTarget.target,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.dependsOnXCTest(path: project.path, name: "UnitTests")

        // Then
        XCTAssertTrue(got)
    }

    func test_dependsOnXCTest_when_direct_dependency_is_XCTest_SDK() {
        // Given
        let project = Project.test()
        let frameworkTarget = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "Framework",
                product: .framework
            )
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    frameworkTarget.target.name: frameworkTarget.target,
                ],
            ],
            dependencies: [
                .target(name: frameworkTarget.target.name, path: project.path): [
                    .testSDK(name: "XCTest"),
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.dependsOnXCTest(path: project.path, name: "Framework")

        // Then
        XCTAssertTrue(got)
    }

    func test_dependsOnXCTest_when_settings_enables_search_paths() {
        // Given
        let project = Project.test()
        let frameworkTarget = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "Framework",
                product: .framework,
                settings: .test(base: [
                    "ENABLE_TESTING_SEARCH_PATHS": "YES",
                ])
            )
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    frameworkTarget.target.name: frameworkTarget.target,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.dependsOnXCTest(path: project.path, name: "Framework")

        // Then
        XCTAssertTrue(got)
    }

    func test_target() {
        // Given
        let path = AbsolutePath.root
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path)

        // Given: Value Graph
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [
                "/": ["App": app, "Framework": framework],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.target(path: "/", name: "App")

        // Then
        XCTAssertEqual(got.map(\.target), app)
    }

    func test_targets() {
        // Given
        let path = AbsolutePath.root
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path)
        let framework = Target.test(name: "Framework", product: .framework)

        // When: Value Graph
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [
                path: ["App": app, "Framework": framework],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.targets(at: path).sorted()

        // Then
        XCTAssertEqual(got.map(\.target), [app, framework])
    }

    func test_directStaticDependencies() {
        // Given
        let path = AbsolutePath.root
        let framework = Target.test(name: "Framework", product: .framework)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let targets: [AbsolutePath: [String: Target]] = [
            path: [
                framework.name: framework,
                staticLibrary.name: staticLibrary,
            ],
        ]
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: framework.name, path: path): Set([.target(name: staticLibrary.name, path: path)]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: path,
            targets: targets,
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.directStaticDependencies(path: path, name: framework.name).sorted()

        // Then
        XCTAssertEqual(
            got,
            [.product(target: staticLibrary.name, productName: staticLibrary.productNameWithExtension, platformFilter: .ios)]
        )
    }

    func test_directLocalTargetDependencies() {
        // Given
        // A -> B -> C
        let project = Project.test()
        let a = Target.test(name: "A")
        let b = Target.test(name: "B")
        let c = Target.test(name: "C")
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: a.name, path: project.path): Set([.target(name: b.name, path: project.path)]),
            .target(name: b.name, path: project.path): Set([.target(name: c.name, path: project.path)]),
        ]
        let targets: [AbsolutePath: [String: Target]] = [project.path: [
            a.name: a,
            b.name: b,
            c.name: c,
        ]]
        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: targets,
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.directLocalTargetDependencies(path: project.path, name: a.name).sorted()

        // Then
        XCTAssertEqual(got.map(\.target), [b])
    }

    func test_directLocalTargetDependencies_returnsLocalProjectTargetsOnly() {
        // Given
        // Project A: A1 -> A2
        //               -> (Project B) B1
        // Project B: B1
        let projectA = Project.test(path: "/ProjectA", name: "ProjectA")
        let projectB = Project.test(path: "/ProjectB", name: "ProjectB")
        let a1 = Target.test(name: "A1")
        let a2 = Target.test(name: "A2")
        let b1 = Target.test(name: "B1")
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
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
        let graph = Graph.test(
            path: projectA.path,
            projects: [projectA.path: projectA, projectB.path: projectB],
            targets: targets,
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.directLocalTargetDependencies(path: projectA.path, name: a1.name).sorted()

        // Then
        XCTAssertEqual(got.map(\.target), [a2])
    }

    func test_directTargetDependencies_returnsAllTargets() {
        // Given
        // Project A: A1 -> A2
        //               -> (Project B) B1
        // Project B: B1
        let projectA = Project.test(path: "/ProjectA", name: "ProjectA")
        let projectB = Project.test(path: "/ProjectB", name: "ProjectB")
        let a1 = Target.test(name: "A1")
        let a2 = Target.test(name: "A2")
        let b1 = Target.test(
            name: "B1"
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
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
        let graph = Graph.test(
            path: projectA.path,
            projects: [projectA.path: projectA, projectB.path: projectB],
            targets: targets,
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.directTargetDependencies(path: projectA.path, name: a1.name).sorted()

        // Then
        XCTAssertEqual(
            got,
            [
                GraphTarget(path: projectA.path, target: a2, project: projectA),
                GraphTarget(path: projectB.path, target: b1, project: projectB),
            ]
        )
    }

    func test_resourceBundleDependencies_returns_an_empty_list_when_a_dependency_can_host_resources() {
        // Given
        // App -> WatchApp -> Bundle
        let project = Project.test()
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .iOS, product: .watch2App)
        let bundle = Target.test(name: "Bundle", platform: .iOS, product: .bundle)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: watchApp.name, path: project.path)]),
            .target(name: watchApp.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                watchApp.name: watchApp,
                bundle.name: bundle,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()

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

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: staticLibrary.name, path: project.path)]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticLibrary.name: staticLibrary,
                bundle.name: bundle,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: bundle.name, productName: bundle.productNameWithExtension, platformFilter: .ios),
        ])
    }

    func test_resourceBundleDependencies_when_the_target_doesnt_support_resources() {
        // Given
        // StaticLibrary -> Bundle
        let project = Project.test()
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                staticLibrary.name: staticLibrary,
                bundle.name: bundle,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: staticLibrary.name).sorted()

        // Then
        XCTAssertEqual(got, [])
    }

    func test_resourceBundleDependencies_fromTargetDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let app = Target.test(name: "App", product: .bundle)
        let project = Project.test(path: "/path/a")

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        // Given: Value graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                bundle.name: bundle,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: bundle.name, productName: bundle.productNameWithExtension, platformFilter: .ios),
        ])
    }

    func test_resourceBundleDependencies_fromProjectDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: projectB.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(name: bundle.name, path: projectA.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: .root,
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [
                projectA.path: [bundle.name: bundle],
                projectB.path: [app.name: app],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: bundle.name, productName: bundle.productNameWithExtension, platformFilter: .ios),
        ])
    }

    func test_resourceBundleDependencies_transitivelyViaSingleStaticFramework() {
        // Given
        let bundle = Target.test(name: "ResourceBundle", product: .bundle)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let projectA = Project.test(path: "/path/a", targets: [staticFramework, bundle])

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b", targets: [app])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticFramework.name, path: projectA.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(name: bundle.name, path: projectA.path): Set([]),
            .target(name: app.name, path: projectB.path): Set([.target(name: staticFramework.name, path: projectA.path)]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: .root,
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [
                projectA.path: [
                    bundle.name: bundle,
                    staticFramework.name: staticFramework,
                ],
                projectB.path: [app.name: app],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: bundle.name, productName: bundle.productNameWithExtension, platformFilter: .ios),
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

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle1.name, path: projectA.path): Set([]),
            .target(name: bundle2.name, path: projectA.path): Set([]),
            .target(name: staticFramework1.name, path: projectA.path): Set([
                .target(name: bundle1.name, path: projectA.path),
                .target(
                    name: staticFramework2.name,
                    path: projectA.path
                ),
            ]),
            .target(name: staticFramework2.name, path: projectA.path): Set([.target(name: bundle2.name, path: projectA.path)]),
            .target(name: app.name, path: projectB.path): Set([.target(name: staticFramework1.name, path: projectA.path)]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: .root,
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [
                projectA.path: [
                    bundle1.name: bundle1,
                    bundle2.name: bundle2,
                    staticFramework1.name: staticFramework1,
                    staticFramework2.name: staticFramework2,
                ],
                projectB.path: [app.name: app],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: bundle1.name, productName: bundle1.productNameWithExtension, platformFilter: .ios),
            .product(target: bundle2.name, productName: bundle2.productNameWithExtension, platformFilter: .ios),
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

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle.name, path: projectA.path): Set([]),
            .target(
                name: staticFramework1.name,
                path: projectA.path
            ): Set([.target(name: staticFramework2.name, path: projectA.path)]),
            .target(name: staticFramework2.name, path: projectA.path): Set([.target(name: bundle.name, path: projectA.path)]),
            .target(
                name: dynamicFramework.name,
                path: projectA.path
            ): Set([.target(name: staticFramework2.name, path: projectA.path)]),
            .target(name: app.name, path: projectB.path): Set([.target(name: dynamicFramework.name, path: projectA.path)]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: .root,
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [
                projectA.path: [
                    bundle.name: bundle,
                    staticFramework1.name: staticFramework1,
                    staticFramework2.name: staticFramework2,
                    dynamicFramework.name: dynamicFramework,
                ],
                projectB.path: [app.name: app],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appResults = subject.resourceBundleDependencies(path: projectB.path, name: app.name).sorted()
        let dynamicFrameworkResults = subject.resourceBundleDependencies(path: projectA.path, name: dynamicFramework.name)
            .sorted()
        let staticFramework1Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework1.name)
            .sorted()
        let staticFramework2Results = subject.resourceBundleDependencies(path: projectA.path, name: staticFramework2.name)
            .sorted()

        // Then
        XCTAssertEqual(appResults, [])
        XCTAssertEqual(dynamicFrameworkResults, [
            .product(target: bundle.name, productName: bundle.productNameWithExtension, platformFilter: .ios),
        ])
        XCTAssertEqual(staticFramework1Results, [])
        XCTAssertEqual(staticFramework2Results, [])
    }

    func test_resourceBundleDependencies_precompiledResourceBundles_testBundle() {
        // Given
        let bundlePath = try! AbsolutePath(validating: "/path/cache/CachedStaticFrameworkA.bundle")
        let bundle = GraphDependency.bundle(path: bundlePath)
        let cachedFramework = GraphDependency.testFramework(
            path: "/path/cache/CachedStaticFrameworkA.framework",
            linking: .static
        )
        let staticFramework = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkProject = Project.test(path: "/path/modules/StaticFrameworkB", targets: [staticFramework])

        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let appProject = Project.test(path: "/path/apps/App", targets: [appTests])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: appTests.name, path: appProject.path): Set([
                .target(name: staticFramework.name, path: staticFrameworkProject.path),
            ]),
            .target(name: staticFramework.name, path: staticFrameworkProject.path): Set([
                cachedFramework,
            ]),
            cachedFramework: Set([
                bundle,
            ]),
        ]
        let graph = Graph.test(
            path: .root,
            projects: [
                staticFrameworkProject.path: staticFrameworkProject,
                appProject.path: appProject,
            ],
            targets: [
                staticFrameworkProject.path: [
                    staticFramework.name: staticFramework,
                ],
                appProject.path: [
                    appTests.name: appTests,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appTestResults = subject.resourceBundleDependencies(
            path: appProject.path,
            name: appTests.name
        ).sorted()
        let frameworkResults = subject.resourceBundleDependencies(
            path: staticFrameworkProject.path,
            name: staticFramework.name
        ).sorted()

        // Then
        XCTAssertEqual(appTestResults, [
            .bundle(path: bundlePath),
        ])
        XCTAssertEqual(frameworkResults, [])
    }

    func test_resourceBundleDependencies_precompiledResourceBundles_staticFramework() {
        // Given
        let bundlePath = try! AbsolutePath(validating: "/path/cache/CachedStaticFrameworkA.bundle")
        let bundle = GraphDependency.bundle(path: bundlePath)
        let cachedFramework = GraphDependency.testFramework(
            path: "/path/cache/CachedStaticFrameworkA.framework",
            linking: .static
        )
        let staticFramework = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkProject = Project.test(path: "/path/modules/StaticFrameworkB", targets: [staticFramework])

        let app = Target.test(name: "App", product: .app)
        let appProject = Project.test(path: "/path/apps/App", targets: [app])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: appProject.path): Set([
                .target(name: staticFramework.name, path: staticFrameworkProject.path),
            ]),
            .target(name: staticFramework.name, path: staticFrameworkProject.path): Set([
                cachedFramework,
            ]),
            cachedFramework: Set([
                bundle,
            ]),
        ]
        let graph = Graph.test(
            path: .root,
            projects: [
                staticFrameworkProject.path: staticFrameworkProject,
                appProject.path: appProject,
            ],
            targets: [
                staticFrameworkProject.path: [
                    staticFramework.name: staticFramework,
                ],
                appProject.path: [
                    app.name: app,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appResults = subject.resourceBundleDependencies(
            path: appProject.path,
            name: app.name
        ).sorted()
        let frameworkResults = subject.resourceBundleDependencies(
            path: staticFrameworkProject.path,
            name: staticFramework.name
        ).sorted()

        // Then
        XCTAssertEqual(appResults, [
            .bundle(path: bundlePath),
        ])
        XCTAssertEqual(frameworkResults, [])
    }

    func test_resourceBundleDependencies_precompiledResourceBundles_dynamicFramework() {
        // Given
        let bundlePath = try! AbsolutePath(validating: "/path/cache/CachedStaticFrameworkA.bundle")
        let bundle = GraphDependency.bundle(path: bundlePath)
        let cachedFramework = GraphDependency.testFramework(
            path: "/path/cache/CachedStaticFrameworkA.framework",
            linking: .static
        )
        let dynamicFramework = Target.test(name: "DynamicFrameworkB", product: .framework)
        let dynamicFrameworkProject = Project.test(path: "/path/modules/StaticFrameworkB", targets: [dynamicFramework])

        let app = Target.test(name: "App", product: .app)
        let appProject = Project.test(path: "/path/apps/App", targets: [app])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: appProject.path): Set([
                .target(name: dynamicFramework.name, path: dynamicFrameworkProject.path),
            ]),
            .target(name: dynamicFramework.name, path: dynamicFrameworkProject.path): Set([
                cachedFramework,
            ]),
            cachedFramework: Set([
                bundle,
            ]),
        ]
        let graph = Graph.test(
            path: .root,
            projects: [
                dynamicFrameworkProject.path: dynamicFrameworkProject,
                appProject.path: appProject,
            ],
            targets: [
                dynamicFrameworkProject.path: [
                    dynamicFramework.name: dynamicFramework,
                ],
                appProject.path: [
                    app.name: app,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appResults = subject.resourceBundleDependencies(
            path: appProject.path,
            name: app.name
        ).sorted()
        let frameworkResults = subject.resourceBundleDependencies(
            path: dynamicFrameworkProject.path,
            name: dynamicFramework.name
        ).sorted()

        // Then
        XCTAssertEqual(appResults, [])
        XCTAssertEqual(frameworkResults, [
            .bundle(path: bundlePath),
        ])
    }

    func test_target_from_dependency() {
        // Given
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [app.name: app]],
            dependencies: [.target(name: app.name, path: project.path): Set()]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.target(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got?.target, app)
    }

    func test_allDependencies() throws {
        // Given
        // App -> StaticLibrary -> Bundle
        let project = Project.test()
        let app = Target.test(name: "App", product: .app)
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary, productName: "StaticLibrary")
        let bundle = Target.test(name: "Bundle", product: .bundle)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: staticLibrary.name, path: project.path)]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticLibrary.name: staticLibrary,
                bundle.name: bundle,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.allProjectDependencies(path: project.path).sorted()

        // Then
        XCTAssertEqual(Set(got), Set([
            .testProduct(target: bundle.name, productName: bundle.productNameWithExtension),
            .testProduct(target: staticLibrary.name, productName: staticLibrary.productNameWithExtension),
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

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([
                .target(name: staticLibrary.name, path: project.path),
                .target(name: frameworkA.name, path: project.path),
            ]),
            .target(name: staticLibrary.name, path: project.path): Set([.target(name: bundle.name, path: project.path)]),
            .target(name: bundle.name, path: project.path): Set([]),
            .target(name: frameworkB.name, path: project.path): Set([]),
            .target(name: frameworkA.name, path: project.path): Set([.target(name: frameworkB.name, path: project.path)]),
        ]

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticLibrary.name: staticLibrary,
                bundle.name: bundle,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.filterDependencies(
            from: .target(name: app.name, path: project.path),
            test: { _ in true },
            skip: {
                if case let GraphDependency.target(name, _) = $0, name == "FrameworkA" {
                    return true
                } else {
                    return false
                }
            }
        )

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
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set([.target(name: dependency.name, path: project.path)]),
            .target(name: dependency.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                target.name: target,
                dependency.name: dependency,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.appExtensionDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got.first?.target.name, "AppExtension")
    }

    func test_appExtensionDependencies_when_dependencyIsStickerPackExtension() throws {
        // When
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let project = Project.test(targets: [target])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set([.target(name: dependency.name, path: project.path)]),
            .target(name: dependency.name, path: project.path): Set([]),
        ]

        // Given: Value graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                target.name: target,
                dependency.name: dependency,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // Given
        let got = subject.appExtensionDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got.first?.target.name, "StickerPackExtension")
    }

    func test_appExtensionDependencies_when_dependencyIsMessageExtension() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let messageExtension = Target.test(name: "MessageExtension", product: .messagesExtension)
        let project = Project.test(targets: [app, messageExtension])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: messageExtension.name, path: project.path)]),
            .target(name: messageExtension.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                messageExtension.name: messageExtension,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.appExtensionDependencies(path: project.path, name: app.name).sorted()

        // Then
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
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [app.name: app, appClip.name: appClip]],
            dependencies: [.target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: appClip.name, path: project.path))]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.appClipDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(got, .init(path: project.path, target: appClip, project: project))
    }

    func test_embeddableFrameworks_when_targetIsNotApp() throws {
        // Given
        let target = Target.test(name: "Main", product: .framework)
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [dependency.name: dependency, target.name: target]],
            dependencies: [
                .target(
                    name: target.name,
                    path: project.path
                ): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertNil(got.first)
    }

    func test_embeddableFrameworks_when_dependencyIsATarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [dependency.name: dependency, target.name: target]],
            dependencies: [
                .target(
                    name: target.name,
                    path: project.path
                ): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(
            got.first,
            GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework", platformFilter: .ios)
        )
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        // Given
        let frameworkPath = try AbsolutePath(validating: "/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let frameworkDependency = GraphDependency.testFramework(
            path: frameworkPath,
            binaryPath: frameworkPath.appending(component: "test"),
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [
                .target(name: target.name, path: project.path): Set(arrayLiteral: frameworkDependency),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got.first, GraphDependencyReference(frameworkDependency))
    }

    func test_embeddableFrameworks_when_transitiveXCFrameworks() throws {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let project = Project.test(targets: [app])

        // Given: Value Graph
        let cDependency = GraphDependency.xcframework(
            path: "/xcframeworks/c.xcframework",
            infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
            primaryBinaryPath: "/xcframeworks/c.xcframework/c",
            linking: .dynamic
        )
        let dDependency = GraphDependency.xcframework(
            path: "/xcframeworks/d.xcframework",
            infoPlist: .test(libraries: [.test(identifier: "id", path: RelativePath("path"), architectures: [.arm64])]),
            primaryBinaryPath: "/xcframeworks/d.xcframework/d",
            linking: .dynamic
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: cDependency),
            cDependency: Set(arrayLiteral: dDependency),
            dDependency: Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [app.name: app]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(cDependency),
            GraphDependencyReference(dDependency),
        ])
    }

    func test_embeddableFrameworks_when_dependencyIsATransitiveFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let frameworkDependency = GraphDependency.testFramework(
            path: "/framework.framework",
            binaryPath: "/framework.framework/framework",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(name: dependency.name, path: project.path): Set(arrayLiteral: frameworkDependency),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target, dependency.name: dependency]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference.product(target: "Dependency", productName: "Dependency.framework", platformFilter: .ios),
            GraphDependencyReference(frameworkDependency),
        ])
    }

    func test_embeddableFrameworks_when_precompiledStaticFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .testFramework(
                path: "/test/StaticFramework.framework",
                binaryPath: "/test/StaticFramework.framework/StaticFramework",
                dsymPath: nil,
                bcsymbolmapPaths: [],
                linking: .static,
                architectures: [.arm64],
                isCarthage: false
            )),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableFrameworks_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: watchExtension.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
            .target(
                name: frameworkA.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                watchExtension.name: watchExtension,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework", platformFilter: .ios),
            .product(target: "FrameworkB", productName: "FrameworkB.framework", platformFilter: .ios),
        ])
    }

    func test_embeddableDependencies_whenHostedTestTarget() throws {
        // Given
        let framework = Target.test(
            name: "Framework",
            product: .framework
        )

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                tests.name: tests,
                framework.name: framework,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_when_nonHostedTestTarget_dynamic_dependencies() throws {
        // Given
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")
        let target = Target.test(name: "LocallyBuiltFramework", product: .framework)

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testFramework(
            path: "/test/test.framework",
            binaryPath: "/test/test.framework/test",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(),
            .target(name: unitTests.name, path: project.path): Set(
                arrayLiteral: .target(name: target.name, path: project.path),
                precompiledDependency
            ),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                unitTests.name: unitTests,
                target.name: target,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_whenHostedTestTarget_transitiveDependencies() throws {
        // Given
        let framework = Target.test(
            name: "Framework",
            product: .framework
        )

        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .framework
        )

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(
                name: staticFramework.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: tests.name, path: project.path): Set(
                arrayLiteral: .target(name: app.name, path: project.path),
                .target(name: staticFramework.name, path: project.path)
            ),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                framework.name: framework,
                staticFramework.name: staticFramework,
                app.name: app,
                tests.name: tests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_embeddableDependencies_whenUITest_andAppPrecompiledDependencies() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testFramework(
            path: "/test/test.framework",
            binaryPath: "/test/test.framework/test",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: precompiledDependency),
            .target(name: uiTests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
            precompiledDependency: Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                uiTests.name: uiTests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.embeddableFrameworks(path: project.path, name: uiTests.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_librariesPublicHeadersFolders() throws {
        // Given
        let target = Target.test(name: "Main")
        let publicHeadersPath = try AbsolutePath(validating: "/test/public/")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testLibrary(
            path: try AbsolutePath(validating: "/test/test.a"),
            publicHeaders: publicHeadersPath,
            linking: .static,
            architectures: []
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.librariesPublicHeadersFolders(
            path: project.path,
            name: target.name
        ).sorted()

        // Then
        XCTAssertEqual(got.first, publicHeadersPath)
    }

    func test_librariesSearchPaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testLibrary(
            path: "/test/test.a",
            publicHeaders: "/test/public/",
            linking: .static,
            architectures: []
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.librariesSearchPaths(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [try AbsolutePath(validating: "/test")])
    }

    func test_linkableDependencies_whenPrecompiled() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testFramework(
            path: "/test/test.framework",
            binaryPath: "/test/test.framework/test",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: precompiledDependency),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got.first, GraphDependencyReference(precompiledDependency))
    }

    func test_linkableAndEmbeddableDependencies_when_appDependensOnPrecompiledStaticBinaryWithPrecompiledStaticBinaryDependency(
    ) throws {
        // App ---(depends on)---> Precompiled static binary (A) ---> Precompiled static binary (B)

        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencyPrecompiledStaticBinaryB = GraphDependency.testFramework(
            path: "/test/StaticFrameworkB.framework",
            binaryPath: "/test/StaticFrameworkB.framework/StaticFrameworkB",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .static,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencyPrecompiledStaticBinaryA = GraphDependency.testFramework(
            path: "/test/StaticFrameworkA.framework",
            binaryPath: "/test/StaticFrameworkA.framework/StaticFrameworkA",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .static,
            architectures: [.arm64],
            isCarthage: false
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: dependencyPrecompiledStaticBinaryA),
            dependencyPrecompiledStaticBinaryA:
                Set(arrayLiteral: dependencyPrecompiledStaticBinaryB),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(dependencyPrecompiledStaticBinaryA),
            GraphDependencyReference(dependencyPrecompiledStaticBinaryB),
        ])

        // When
        let embeddable = subject.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertTrue(embeddable.isEmpty)
    }

    func test_linkableAndEmbeddableDependencies_when_appDependensOnPrecompiledDynamicBinaryWithPrecompiledDynamicBinaryDependency(
    ) throws {
        // App ---(depends on)---> Precompiled dynamic binary (A) ----> Precompiled dynamic binary (B)

        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencyPrecompiledDynamicBinaryB = GraphDependency.testFramework(
            path: "/test/DynamicFrameworkB.framework",
            binaryPath: "/test/DynamicFrameworkB.framework/DynamicFrameworkB",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencyPrecompiledDynamicBinaryA = GraphDependency.testFramework(
            path: "/test/DynamicFrameworkA.framework",
            binaryPath: "/test/DynamicFrameworkA.framework/DynamicFrameworkA",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: dependencyPrecompiledDynamicBinaryA),
            dependencyPrecompiledDynamicBinaryA:
                Set(arrayLiteral: dependencyPrecompiledDynamicBinaryB),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryA),
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryB),
        ])

        // When
        let embeddable = subject.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(embeddable, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryA),
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryB),
        ])
    }

    func test_linkableAndEmbeddableDependencies_when_appDependensOnPrecompiledStaticBinaryWithPrecompiledDynamicBinaryDependency(
    ) throws {
        // App ---(depends on)---> Precompiled static binary (A) ----> Precompiled dynamic binary (B)

        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencyPrecompiledDynamicBinaryB = GraphDependency.testFramework(
            path: "/test/DynamicFrameworkB.framework",
            binaryPath: "/test/DynamicFrameworkB.framework/DynamicFrameworkB",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencyPrecompiledStaticBinaryA = GraphDependency.testFramework(
            path: "/test/StaticFrameworkA.framework",
            binaryPath: "/test/StaticFrameworkA.framework/StaticFrameworkA",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .static,
            architectures: [.arm64],
            isCarthage: false
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: dependencyPrecompiledStaticBinaryA),
            dependencyPrecompiledStaticBinaryA:
                Set(arrayLiteral: dependencyPrecompiledDynamicBinaryB),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryB),
            GraphDependencyReference(dependencyPrecompiledStaticBinaryA),
        ])

        // When
        let embeddable = subject.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(embeddable, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryB),
        ])
    }

    func test_linkableAndEmbeddableDependencies_when_appDependensOnPrecompiledDynamicBinaryWithPrecompiledStaticBinaryDependency(
    ) throws {
        // App ---(depends on)---> Precompiled dynamic binary (A) ----> Precompiled static binary (B)

        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencyPrecompiledStaticBinaryB = GraphDependency.testFramework(
            path: "/test/StaticFrameworkB.framework",
            binaryPath: "/test/StaticFrameworkB.framework/StaticFrameworkB",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .static,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencyPrecompiledDynamicBinaryA = GraphDependency.testFramework(
            path: "/test/DynamicFrameworkA.framework",
            binaryPath: "/test/DynamicFrameworkA.framework/DynamicFrameworkA",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: dependencyPrecompiledDynamicBinaryA),
            dependencyPrecompiledDynamicBinaryA:
                Set(arrayLiteral: dependencyPrecompiledStaticBinaryB),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryA),
            GraphDependencyReference(dependencyPrecompiledStaticBinaryB),
        ])

        // When
        let embeddable = subject.embeddableFrameworks(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(embeddable, [
            GraphDependencyReference(dependencyPrecompiledDynamicBinaryA),
        ])
    }

    func test_linkableFrameworks_when_staticFrameworkDependsOnTransitivePrecompiledStaticFramework() throws {
        // Given
        // App
        //  -> StaticFramework (Target .staticFramework)
        //     -> precompiledStaticFrameworkA (Framework .static)
        //        -> precompiledStaticFrameworkB (Framework .static)
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, staticFramework])
        let precompiledStaticFrameworkA = GraphDependency.testFramework(
            path: "/test/StaticFrameworkA.framework",
            binaryPath: "/test/StaticFrameworkA.framework/StaticFrameworkA",
            linking: .static
        )
        let precompiledStaticFrameworkB = GraphDependency.testFramework(
            path: "/test/StaticFrameworkB.framework",
            binaryPath: "/test/StaticFrameworkB.framework/StaticFrameworkB",
            linking: .static
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
            ],
            .target(name: staticFramework.name, path: project.path): [
                precompiledStaticFrameworkA,
            ],
            precompiledStaticFrameworkA: [
                precompiledStaticFrameworkB,
            ],
        ]
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let results = try subject.linkableDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(results.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticFrameworkA),
            GraphDependencyReference(precompiledStaticFrameworkB),
        ])
    }

    func test_linkableDependencies_whenALibraryTarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(name: dependency.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target, dependency.name: dependency]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got.first, .product(target: "Dependency", productName: "libDependency.a", platformFilter: .ios))
    }

    func test_linkableDependencies_whenAFrameworkTarget() throws {
        // Given
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): Set(arrayLiteral: .target(name: dependency.name, path: project.path)),
            .target(
                name: dependency.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticDependency.name, path: project.path)),
            .target(name: staticDependency.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                target.name: target,
                dependency.name: dependency,
                staticDependency.name: staticDependency,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(
            path: project.path,
            name: target.name
        ).sorted()

        // Then
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first, .product(target: "Dependency", productName: "Dependency.framework", platformFilter: .ios))

        let frameworkGot = try subject.linkableDependencies(path: project.path, name: dependency.name)

        XCTAssertEqual(frameworkGot.count, 1)
        XCTAssertTrue(
            frameworkGot
                .contains(.product(target: "StaticDependency", productName: "libStaticDependency.a", platformFilter: .ios))
        )
    }

    func test_linkableDependencies_transitiveDynamicLibrariesOneStaticHop() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .staticFramework,
            dependencies: []
        )
        let dynamicFramework = Target.test(
            name: "DynamicFramework",
            product: .framework,
            dependencies: []
        )
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(
                name: staticFramework.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework.name, path: project.path)),
            .target(name: dynamicFramework.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticFramework.name: staticFramework,
                dynamicFramework.name: dynamicFramework,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(
            got,
            [
                GraphDependencyReference
                    .product(target: "DynamicFramework", productName: "DynamicFramework.framework", platformFilter: .ios),
                GraphDependencyReference.product(
                    target: "StaticFramework",
                    productName: "StaticFramework.framework",
                    platformFilter: .ios
                ),
            ]
        )
    }

    func test_linkableDependencies_transitiveDynamicLibrariesThreeHops() throws {
        // Given
        let dynamicFramework1 = Target.test(
            name: "DynamicFramework1",
            product: .framework,
            dependencies: []
        )
        let dynamicFramework2 = Target.test(
            name: "DynamicFramework2",
            product: .framework,
            dependencies: []
        )
        let staticFramework1 = Target.test(
            name: "StaticFramework1",
            product: .staticLibrary,
            dependencies: []
        )
        let staticFramework2 = Target.test(
            name: "StaticFramework2",
            product: .staticLibrary,
            dependencies: []
        )
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework1.name, path: project.path)),
            .target(
                name: dynamicFramework1.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework1.name, path: project.path)),
            .target(
                name: staticFramework1.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework2.name, path: project.path)),
            .target(
                name: staticFramework2.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework2.name, path: project.path)),
            .target(name: dynamicFramework2.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                dynamicFramework1.name: dynamicFramework1,
                dynamicFramework2.name: dynamicFramework2,
                staticFramework1.name: staticFramework1,
                staticFramework2.name: staticFramework2,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appGot = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicFramework1Got = try subject.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()

        // Then
        XCTAssertEqual(appGot, [
            GraphDependencyReference.product(
                target: "DynamicFramework1",
                productName: "DynamicFramework1.framework",
                platformFilter: .ios
            ),
        ])
        XCTAssertEqual(dynamicFramework1Got, [
            GraphDependencyReference.product(
                target: "DynamicFramework2",
                productName: "DynamicFramework2.framework",
                platformFilter: .ios
            ),
            GraphDependencyReference.product(
                target: "StaticFramework1",
                productName: "libStaticFramework1.a",
                platformFilter: .ios
            ),
            GraphDependencyReference.product(
                target: "StaticFramework2",
                productName: "libStaticFramework2.a",
                platformFilter: .ios
            ),
        ])
    }

    func test_linkableDependencies_transitiveDynamicLibrariesCheckNoDuplicatesInParentDynamic() throws {
        // Given
        let dynamicFramework1 = Target.test(
            name: "DynamicFramework1",
            product: .framework,
            dependencies: []
        )
        let dynamicFramework2 = Target.test(
            name: "DynamicFramework2",
            product: .framework,
            dependencies: []
        )
        let dynamicFramework3 = Target.test(
            name: "DynamicFramework3",
            product: .framework,
            dependencies: []
        )
        let staticFramework1 = Target.test(
            name: "StaticFramework1",
            product: .staticLibrary,
            dependencies: []
        )
        let staticFramework2 = Target.test(
            name: "StaticFramework2",
            product: .staticLibrary,
            dependencies: []
        )

        let app = Target.test(name: "App", product: .app)

        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework1.name, path: project.path)),
            .target(
                name: dynamicFramework1.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework2.name, path: project.path)),
            .target(
                name: dynamicFramework2.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework1.name, path: project.path)),
            .target(
                name: staticFramework1.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework2.name, path: project.path)),
            .target(
                name: staticFramework2.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework3.name, path: project.path)),
            .target(name: dynamicFramework3.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                dynamicFramework1.name: dynamicFramework1,
                dynamicFramework2.name: dynamicFramework2,
                staticFramework1.name: staticFramework1,
                staticFramework2.name: staticFramework2,
                dynamicFramework3.name: dynamicFramework3,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let dynamicFramework1Got = try subject.linkableDependencies(path: project.path, name: dynamicFramework1.name).sorted()

        // Then
        XCTAssertEqual(
            dynamicFramework1Got,
            [
                GraphDependencyReference
                    .product(target: "DynamicFramework2", productName: "DynamicFramework2.framework", platformFilter: .ios),
            ]
        )
    }

    func test_linkableDependencies_transitiveSDKDependenciesStatic() throws {
        // Given
        let staticFrameworkA = Target.test(
            name: "StaticFrameworkA",
            product: .staticFramework,
            dependencies: [.sdk(name: "some.framework", status: .optional)]
        )
        let staticFrameworkB = Target.test(
            name: "StaticFrameworkB",
            product: .staticFramework,
            dependencies: []
        )
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFrameworkB.name, path: project.path)),
            .target(
                name: staticFrameworkB.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFrameworkA.name, path: project.path)),
            .target(name: staticFrameworkA.name, path: project.path): Set(arrayLiteral: .sdk(
                name: "some.framework",
                path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                status: .optional,
                source: .developer
            )),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkA.name: staticFrameworkA,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got.compactMap(sdkDependency), [
            SDKPathAndStatus(name: "some.framework", status: .optional),
        ])
    }

    func test_linkableDependencies_transitiveSDKDependenciesDynamic() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .staticFramework,
            dependencies: [.sdk(name: "some.framework", status: .optional)]
        )
        let dynamicFramework = Target.test(
            name: "DynamicFramework",
            product: .framework,
            dependencies: []
        )
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: dynamicFramework.name, path: project.path)),
            .target(
                name: dynamicFramework.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .sdk(
                name: "some.framework",
                path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                status: .optional,
                source: .developer
            )),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticFramework.name: staticFramework,
                dynamicFramework.name: dynamicFramework,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appGot = try subject.linkableDependencies(path: project.path, name: app.name).sorted()
        let dynamicGot = try subject.linkableDependencies(path: project.path, name: dynamicFramework.name).sorted()

        // Then
        XCTAssertEqual(appGot.compactMap(sdkDependency), [])
        XCTAssertEqual(
            dynamicGot.compactMap(sdkDependency),
            [SDKPathAndStatus(name: "some.framework", status: .optional)]
        )
    }

    func test_linkableDependencies_transitiveSDKDependenciesNotDuplicated() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .staticFramework,
            dependencies: [.sdk(name: "some.framework", status: .optional)]
        )
        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [.sdk(name: "some.framework", status: .optional)]
        )

        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: staticFramework.name, path: project.path)),
            .target(name: staticFramework.name, path: project.path): Set(arrayLiteral: .sdk(
                name: "some.framework",
                path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/some.framework",
                status: .optional,
                source: .developer
            )),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got.compactMap(sdkDependency), [SDKPathAndStatus(name: "some.framework", status: .optional)])
    }

    func test_linkableDependencies_transitiveSDKDependenciesImmediateDependencies() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFrameworkA",
            product: .staticFramework,
            dependencies: [
                .sdk(name: "thingone.framework", status: .optional),
                .sdk(name: "thingtwo.framework", status: .required),
            ]
        )

        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticFramework.name, path: project.path): Set(
                arrayLiteral: .sdk(
                    name: "thingone.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/thingone.framework",
                    status: .optional,
                    source: .developer
                ),
                .sdk(
                    name: "thingtwo.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/thingtwo.framework",
                    status: .required,
                    source: .developer
                )
            ),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [staticFramework.name: staticFramework]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: staticFramework.name).sorted()

        // Then
        XCTAssertEqual(
            got.compactMap(sdkDependency),
            [
                SDKPathAndStatus(name: "thingone.framework", status: .optional),
                SDKPathAndStatus(name: "thingtwo.framework", status: .required),
            ]
        )
    }

    func test_linkableDependencies_NoTransitiveSDKDependenciesForStaticFrameworks() throws {
        // Given
        let staticFrameworkA = Target.test(
            name: "StaticFrameworkA",
            product: .staticFramework,
            dependencies: [.sdk(name: "ThingOne.framework", status: .optional)]
        )
        let staticFrameworkB = Target.test(
            name: "StaticFrameworkB",
            product: .staticFramework,
            dependencies: [.sdk(name: "ThingTwo.framework", status: .optional)]
        )

        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticFrameworkA.name, path: project.path): Set(
                arrayLiteral: .target(name: staticFrameworkB.name, path: project.path),
                .sdk(
                    name: "ThingOne.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/ThingOne.framework",
                    status: .optional,
                    source: .developer
                )
            ),
            .target(name: staticFrameworkB.name, path: project.path): Set(arrayLiteral: .sdk(
                name: "ThingTwo.framework",
                path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/ThingTwo.framework",
                status: .optional,
                source: .developer
            )),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: staticFrameworkA.name).sorted()

        // Then
        XCTAssertEqual(
            got.compactMap(sdkDependency),
            [SDKPathAndStatus(name: "ThingOne.framework", status: .optional)]
        )
    }

    func test_linkableDependencies_includeTransitivePrecompiledDependenciesOfStaticFrameworks() throws {
        // Given
        // App > StaticFramework > PrecompiledDynamicFramework
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let precompiled = GraphDependency.framework(
            path: "/path/to/frameworks/precompiled.framework",
            binaryPath: "/path/to/frameworks/precompiled.framework/precompiled",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let project = Project.test(path: "/path/project", targets: [app, staticFramework])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): Set([
                    .target(name: staticFramework.name, path: project.path),
                ]),
                .target(name: staticFramework.name, path: project.path): Set([
                    precompiled,
                ]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let result = try subject.linkableDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(result.sorted(), [
            .product(target: "StaticFramework", productName: "StaticFramework.framework", platformFilter: .ios),
            .framework(
                path: "/path/to/frameworks/precompiled.framework",
                binaryPath: "/path/to/frameworks/precompiled.framework/precompiled",
                isCarthage: false,
                dsymPath: nil,
                bcsymbolmapPaths: [],
                linking: .dynamic,
                architectures: [.arm64],
                product: .framework
            ),
        ])
    }

    func test_linkableDependencies_doNotIncludeTransitivePrecompiledDependenciesOfDynamicFrameworks() throws {
        // Given
        // App > DynamicFramework > PrecompiledDynamicFramework
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "DynamicFramework", product: .framework)
        let precompiled = GraphDependency.framework(
            path: "/path/to/frameworks/precompiled.framework",
            binaryPath: "/path/to/frameworks/precompiled.framework/precompiled",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let project = Project.test(path: "/path/project", targets: [app, framework])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    framework.name: framework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): Set([
                    .target(name: framework.name, path: project.path),
                ]),
                .target(name: framework.name, path: project.path): Set([
                    precompiled,
                ]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let result = try subject.linkableDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(result.sorted(), [
            .product(target: "DynamicFramework", productName: "DynamicFramework.framework", platformFilter: .ios),
        ])
    }

    func test_linkableDependencies_doNotIncludeTransitivePrecompiledDependenciesOfDynamicFrameworks2() throws {
        // Given
        // App > StaticFramework > DynamicFramework > PrecompiledDynamicFramework
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let framework = Target.test(name: "DynamicFramework", product: .framework)
        let precompiled = GraphDependency.framework(
            path: "/path/to/frameworks/precompiled.framework",
            binaryPath: "/path/to/frameworks/precompiled.framework/precompiled",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let project = Project.test(path: "/path/project", targets: [app, staticFramework, framework])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                    framework.name: framework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): Set([
                    .target(name: staticFramework.name, path: project.path),
                ]),
                .target(name: staticFramework.name, path: project.path): Set([
                    .target(name: framework.name, path: project.path),
                ]),
                .target(name: framework.name, path: project.path): Set([
                    precompiled,
                ]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let result = try subject.linkableDependencies(path: project.path, name: app.name)

        // Then
        XCTAssertEqual(result.sorted(), [
            .product(target: "DynamicFramework", productName: "DynamicFramework.framework", platformFilter: .ios),
            .product(target: "StaticFramework", productName: "StaticFramework.framework", platformFilter: .ios),
        ])
    }

    func test_linkableDependencies_when_watchExtension() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: watchExtension.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(
                name: frameworkA.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                watchExtension.name: watchExtension,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework", platformFilter: .ios),
        ])
    }

    func test_linkableDependencies_when_watchExtension_staticDependency() throws {
        // Given
        let frameworkA = Target.test(name: "FrameworkA", product: .staticFramework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let watchExtension = Target.test(name: "WatchExtension", product: .watch2Extension)
        let project = Project.test(targets: [watchExtension, frameworkA, frameworkB])

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: watchExtension.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkA.name, path: project.path)),
            .target(
                name: frameworkA.name,
                path: project.path
            ): Set(arrayLiteral: .target(name: frameworkB.name, path: project.path)),
            .target(name: frameworkB.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                watchExtension.name: watchExtension,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: watchExtension.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: "FrameworkA", productName: "FrameworkA.framework", platformFilter: .ios),
            .product(target: "FrameworkB", productName: "FrameworkB.framework", platformFilter: .ios),
        ])
    }

    func test_linkableDependencies_whenHostedTestTarget_withCommonStaticProducts() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .staticFramework
        )

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
            ],
            .target(name: staticFramework.name, path: project.path): [],
            .target(name: tests.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
                .target(name: app.name, path: project.path),
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                staticFramework.name: staticFramework,
                tests.name: tests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        // common static products are not linked in the test target
        // as the are already present in the test host
        XCTAssertTrue(got.isEmpty)
    }

    func test_linkableDependencies_whenAppClipHostedTestTarget_withCommonStaticProducts() throws {
        // Given
        let staticFramework = Target.test(
            name: "StaticFramework",
            product: .staticFramework
        )

        let appClip = Target.test(name: "AppClip", product: .appClip)
        let tests = Target.test(name: "AppClipTests", product: .unitTests)
        let project = Project.test(path: "/path/a")
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: appClip.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
            ],
            .target(name: staticFramework.name, path: project.path): [],
            .target(name: tests.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
                .target(name: appClip.name, path: project.path),
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                appClip.name: appClip,
                staticFramework.name: staticFramework,
                tests.name: tests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        // common static products are not linked in the test target
        // as the are already present in the test host
        XCTAssertTrue(got.isEmpty)
    }

    func test_linkableDependencies_whenHostedTestTarget_withCommonDynamicProducts() throws {
        // Given
        let framework = Target.test(
            name: "Framework",
            product: .framework
        )

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(
                arrayLiteral: .target(name: framework.name, path: project.path),
                .target(name: app.name, path: project.path)
            ),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                framework.name: framework,
                tests.name: tests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertEqual(got, [
            .product(target: "Framework", productName: "Framework.framework", platformFilter: .ios),
        ])
    }

    func test_linkableDependencies_whenHostedTestTarget_doNotIncludeRedundantDependencies() throws {
        // Given
        let framework = Target.test(
            name: "Framework",
            product: .framework
        )

        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(arrayLiteral: .target(name: framework.name, path: project.path)),
            .target(name: framework.name, path: project.path): Set(),
            .target(name: tests.name, path: project.path): Set(arrayLiteral: .target(name: app.name, path: project.path)),
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                framework.name: framework,
                tests.name: tests,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: tests.name).sorted()

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_linkableDependencies_when_appClipSDKNode() throws {
        // Given
        let target = Target.test(name: "AppClip", product: .appClip)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): [
                .sdk(
                    name: "AppClip.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/AppClip.framework",
                    status: .required,
                    source: .system
                ),
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name).sorted()

        // Then
        let path = try SystemFrameworkMetadataProvider().loadMetadata(
            sdkName: "AppClip.framework",
            status: .required,
            platform: .iOS,
            source: .system
        )
        .path
        XCTAssertEqual(
            got, [
                .sdk(path: path, status: .required, source: .system),
            ]
        )
    }

    func test_embeddableFrameworks_when_appClipDependsOnDynamicFramework() throws {
        // Given
        let appClipTarget = Target.test(name: "AppClip", product: .appClip)
        let frameworkTarget = Target.test(name: "MyFramework", product: .framework)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: appClipTarget.name, path: project.path): [
                .target(name: frameworkTarget.name, path: project.path),
            ],
        ]
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    appClipTarget.name: appClipTarget,
                    frameworkTarget.name: frameworkTarget,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let result = subject.embeddableFrameworks(path: project.path, name: appClipTarget.name).sorted()

        // Then
        XCTAssertEqual(result, [
            .product(
                target: "MyFramework",
                productName: "MyFramework.framework",
                platformFilter: .ios
            ),
        ])
    }

    func test_linkableDependencies_when_dependencyIsAFramework() throws {
        // Given
        let frameworkPath = try AbsolutePath(validating: "/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let frameworkDependency = GraphDependency.testFramework(
            path: frameworkPath,
            binaryPath: frameworkPath.appending(component: "test"),
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [
                .target(name: target.name, path: project.path): Set(arrayLiteral: frameworkDependency),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(frameworkDependency),
        ])
    }

    func test_linkableFrameworks_when_precompiledStaticFramework() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let frameworkDependency = GraphDependency.testFramework(
            path: "/test/StaticFramework.framework",
            binaryPath: "/test/StaticFramework.framework/StaticFramework",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .static,
            architectures: [.arm64],
            isCarthage: false
        )
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: target.name, path: project.path): [
                frameworkDependency,
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: target.name)

        // Then
        XCTAssertEqual(got, [
            GraphDependencyReference(frameworkDependency),
        ])
    }

    func test_when_staticFrameworkDependsOnPrecompiledStaticFramework() throws {
        // Given
        // App > StaticFramework > PrecompiledStaticFramework
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, staticFramework])
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: staticFramework.name, path: project.path),
                ],
                .target(name: staticFramework.name, path: project.path): [
                    precompiledStaticFramework,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: app.name
        )
        let staticFrameworkLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkCopyProducts = subject.copyProductDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkSearchPaths = try subject.searchablePathDependencies(
            path: project.path,
            name: staticFramework.name
        )

        // Then
        // To avoid duplicate symbols, the linking only takes place in the final target that supports linking
        // rather than at every intermediate static framework / library target.
        //
        // For precompiled static `.framework`s, ensuring search paths are updated should allow the intermediate
        // static frameworks to see their symbols during compilation.
        XCTAssertEqual(appLinkableProducts.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticFramework),
        ])
        XCTAssertEqual(staticFrameworkLinkableProducts.sorted(), [])
        XCTAssertEqual(staticFrameworkCopyProducts.sorted(), [])
        XCTAssertEqual(staticFrameworkSearchPaths.sorted(), [
            GraphDependencyReference(precompiledStaticFramework),
        ])
    }

    func test_when_staticFrameworkDependsOnPrecompiledStaticLibaryXCFramework() throws {
        // Given
        // App > StaticFramework > PrecompiledStaticXCFramework
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, staticFramework])
        let precompiledStaticXCFramework = GraphDependency.testXCFramework(
            path: "/test/PrecompiledStaticFramework.xcframework",
            linking: .static
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: staticFramework.name, path: project.path),
                ],
                .target(name: staticFramework.name, path: project.path): [
                    precompiledStaticXCFramework,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: app.name
        )
        let staticFrameworkLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkCopyProducts = subject.copyProductDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkSearchPaths = try subject.searchablePathDependencies(
            path: project.path,
            name: staticFramework.name
        )

        // Then
        // To avoid duplicate symbols, the linking only takes place in the final target that supports linking
        // rather than at every intermediate static framework / library target.
        //
        // For precompiled static `.xcframework`s, ensuring they are part of the copy products build phase
        // allows the intermediate static frameworks to see their symbols during compilation.
        XCTAssertEqual(appLinkableProducts.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticXCFramework),
        ])
        XCTAssertEqual(staticFrameworkLinkableProducts.sorted(), [])
        XCTAssertEqual(staticFrameworkCopyProducts.sorted(), [
            GraphDependencyReference(precompiledStaticXCFramework),
        ])
        XCTAssertEqual(staticFrameworkSearchPaths.sorted(), [])
    }

    func test_when_staticFrameworkDependsOnPrecompiledStaticLibary() throws {
        // Given
        // App > StaticFramework > PrecompiledStaticXCFramework
        let app = Target.test(name: "App", product: .app)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, staticFramework])
        let precompiledStaticLibrary = GraphDependency.testLibrary(
            path: "/test/PrecompiledStaticLibrary/PrecompiledStaticLibrary.a",
            linking: .static,
            swiftModuleMap: "/test/PrecompiledStaticLibrary/PrecompiledStaticLibrary.swiftmodule"
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            targets: [
                project.path: [
                    app.name: app,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: staticFramework.name, path: project.path),
                ],
                .target(name: staticFramework.name, path: project.path): [
                    precompiledStaticLibrary,
                ],
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let appLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: app.name
        )
        let appLibrarySearchPaths = try subject.librariesSearchPaths(
            path: project.path,
            name: app.name
        )
        let staticFrameworkLinkableProducts = try subject.linkableDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkCopyProducts = subject.copyProductDependencies(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkLibrarySearchPaths = try subject.librariesSearchPaths(
            path: project.path,
            name: staticFramework.name
        )
        let staticFrameworkSwiftIncludePaths = subject.librariesSwiftIncludePaths(
            path: project.path,
            name: staticFramework.name
        )

        // Then
        // To avoid duplicate symbols, the linking only takes place in the final target that supports linking
        // rather than at every intermediate static framework / library target.
        //
        // For precompiled static library `.a`, ensuring the searc and swift include paths are set
        // allows the intermediate static frameworks to see their symbols during compilation.
        XCTAssertEqual(appLinkableProducts.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticLibrary),
        ])
        XCTAssertEqual(appLibrarySearchPaths.sorted(), [
            "/test/PrecompiledStaticLibrary",
        ])
        XCTAssertEqual(staticFrameworkLinkableProducts.sorted(), [])
        XCTAssertEqual(staticFrameworkCopyProducts.sorted(), [])
        XCTAssertEqual(staticFrameworkLibrarySearchPaths.sorted(), [
            "/test/PrecompiledStaticLibrary",
        ])
        XCTAssertEqual(staticFrameworkSwiftIncludePaths.sorted(), [
            "/test/PrecompiledStaticLibrary",
        ])
    }

    func test_linkableFrameworks_when_transitivePrecompiledStaticFramework() throws {
        // Given
        let unitTests = Target.test(name: "MyStaticFrameworkTests", product: .unitTests)
        let staticFramework = Target.test(name: "MyStaticFramework", product: .staticFramework)
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let project = Project.test(targets: [staticFramework, unitTests])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: unitTests.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
            ],
            .target(name: staticFramework.name, path: project.path): [
                precompiledStaticFramework,
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    unitTests.name: unitTests,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = try subject.linkableDependencies(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(got.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticFramework),
        ])
    }

    func test_linkableFrameworks_when_transitivePrecompiledStaticFrameworkLinkedByDynamicFramework() throws {
        // Given
        let unitTests = Target.test(name: "MyDynamicFrameworkTests", product: .unitTests)
        let dynamicFramework = Target.test(name: "MyDynamicFramework", product: .framework)
        let staticFramework = Target.test(name: "MyStaticFramework", product: .staticFramework)
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let project = Project.test(targets: [dynamicFramework, staticFramework, unitTests])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: unitTests.name, path: project.path): [
                .target(name: dynamicFramework.name, path: project.path),
            ],
            .target(name: dynamicFramework.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
            ],
            .target(name: staticFramework.name, path: project.path): [
                precompiledStaticFramework,
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    unitTests.name: unitTests,
                    dynamicFramework.name: dynamicFramework,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let frameworkResults = try subject.linkableDependencies(path: project.path, name: dynamicFramework.name)
        let testResults = try subject.linkableDependencies(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(frameworkResults.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticFramework),
        ])
        XCTAssertEqual(testResults.sorted(), [
            .product(
                target: dynamicFramework.name,
                productName: dynamicFramework.productNameWithExtension,
                platformFilter: .ios
            ),
        ])
    }

    func test_linkableFrameworks_when_precompiledStaticFrameworkLinkedByHostApp() throws {
        // Given
        let hostApp = Target.test(name: "App", product: .app)
        let unitTests = Target.test(name: "AppTests", product: .unitTests)
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let project = Project.test(targets: [hostApp, unitTests])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: hostApp.name, path: project.path): [
                precompiledStaticFramework,
            ],
            .target(name: unitTests.name, path: project.path): [
                .target(name: hostApp.name, path: project.path),
                precompiledStaticFramework,
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    hostApp.name: hostApp,
                    unitTests.name: unitTests,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let results = try subject.linkableDependencies(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(results.sorted(), [])
    }

    func test_linkableFrameworks_when_transitivePrecompiledStaticFrameworkLinkedByHostApp() throws {
        // Given
        let hostApp = Target.test(name: "App", product: .app)
        let unitTests = Target.test(name: "MyHostAppTests", product: .unitTests)
        let staticFramework = Target.test(name: "MyStaticFramework", product: .staticFramework)
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let project = Project.test(targets: [hostApp, unitTests])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: hostApp.name, path: project.path): [
                precompiledStaticFramework,
            ],
            .target(name: staticFramework.name, path: project.path): [
                precompiledStaticFramework,
            ],
            .target(name: unitTests.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
                .target(name: hostApp.name, path: project.path),
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    hostApp.name: hostApp,
                    unitTests.name: unitTests,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let results = try subject.linkableDependencies(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(results.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
        ])
    }

    func test_searchablePathDependencies_when_transitivePrecompiledStaticFrameworkLinkedByHostApp() throws {
        // Given
        let hostApp = Target.test(name: "App", product: .app)
        let unitTests = Target.test(name: "MyHostAppTests", product: .unitTests)
        let staticFramework = Target.test(name: "MyStaticFramework", product: .staticFramework)
        let precompiledStaticFramework = GraphDependency.testFramework(
            path: "/test/PrecompiledStaticFramework.framework",
            binaryPath: "/test/PrecompiledStaticFramework.framework/PrecompiledStaticFramework",
            linking: .static
        )
        let project = Project.test(targets: [hostApp, unitTests])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: hostApp.name, path: project.path): [
                precompiledStaticFramework,
            ],
            .target(name: staticFramework.name, path: project.path): [
                precompiledStaticFramework,
            ],
            .target(name: unitTests.name, path: project.path): [
                .target(name: staticFramework.name, path: project.path),
                .target(name: hostApp.name, path: project.path),
            ],
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    hostApp.name: hostApp,
                    unitTests.name: unitTests,
                    staticFramework.name: staticFramework,
                ],
            ],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let results = try subject.searchablePathDependencies(path: project.path, name: unitTests.name)

        // Then
        XCTAssertEqual(results.sorted(), [
            .product(
                target: staticFramework.name,
                productName: staticFramework.productNameWithExtension,
                platformFilter: .ios
            ),
            GraphDependencyReference(precompiledStaticFramework),
        ])
    }

    func test_librariesSwiftIncludePaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let project = Project.test(targets: [target])

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [
                .target(name: target.name, path: project.path): Set([
                    .testLibrary(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap"),
                    .testLibrary(path: "/test/another.b"),
                ]),
                .testLibrary(path: "/test/test.a", swiftModuleMap: "/test/modules/test.swiftmodulemap"): Set([]),
                .testLibrary(path: "/test/another.b"): Set([]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.librariesSwiftIncludePaths(path: project.path, name: target.name).sorted()

        // Then
        XCTAssertEqual(got, [try AbsolutePath(validating: "/test/modules")])
    }

    func test_runPathSearchPaths() throws {
        // Given
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testFramework(
            path: "/test/test.famework",
            binaryPath: "/test/test.framework/test",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let precompiledBDependency = GraphDependency.testFramework(
            path: "/test/testb.famework",
            binaryPath: "/test/testb.framework/testb",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [unitTests.name: unitTests]],
            dependencies: [
                .target(name: unitTests.name, path: project.path): Set([precompiledDependency, precompiledBDependency]),
                precompiledDependency: Set(),
                precompiledBDependency: Set(),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertEqual(
            got,
            [try AbsolutePath(validating: "/test")]
        )
    }

    func test_runPathSearchPaths_when_unit_tests_with_hosted_target() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let unitTests = Target.test(name: "AppUnitTests", product: .unitTests)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let precompiledDependency = GraphDependency.testFramework(
            path: "/test/test.famework",
            binaryPath: "/test/test.framework/test",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                unitTests.name: unitTests,
                app.name: app,
            ]],
            dependencies: [
                .target(
                    name: unitTests.name,
                    path: project.path
                ): Set([precompiledDependency, .target(name: app.name, path: project.path)]),
                .target(name: app.name, path: project.path): Set([]),
                precompiledDependency: Set(),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.runPathSearchPaths(path: project.path, name: unitTests.name).sorted()

        // Then
        XCTAssertEmpty(got)
    }

    func test_hostTargetNode_watchApp() {
        // Given
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                watchApp.name: watchApp,
            ]],
            dependencies: [
                .target(name: app.name, path: project.path): Set([.target(name: watchApp.name, path: project.path)]),
                .target(name: watchApp.name, path: project.path): Set([]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.hostTargetFor(path: project.path, name: "WatchApp")

        // Then
        XCTAssertEqual(got?.target, app)
    }

    func test_hostTargetNode_watchAppExtension() {
        // Given
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let watchAppExtension = Target.test(name: "WatchAppExtension", platform: .watchOS, product: .watch2Extension)
        let project = Project.test(path: "/path/a")

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                watchAppExtension.name: watchAppExtension,
                watchApp.name: watchApp,
            ]],
            dependencies: [
                .target(
                    name: watchApp.name,
                    path: project.path
                ): Set([.target(name: watchAppExtension.name, path: project.path)]),
                .target(name: watchAppExtension.name, path: project.path): Set([]),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.hostTargetFor(path: project.path, name: "WatchAppExtension")

        // Then
        XCTAssertEqual(got?.target, watchApp)
    }

    func test_apps() {
        // Given
        let macosApp = Target.test(name: "MacOS", platform: .macOS, product: .app)
        let tvosApp = Target.test(name: "tvOS", platform: .tvOS, product: .app)
        let framework = Target.test(name: "Framework", platform: .iOS, product: .framework)
        let project = Project.test(path: "/project")

        // Given: Value Graph
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                macosApp.name: macosApp,
                tvosApp.name: tvosApp,
                framework.name: framework,
            ]],
            dependencies: [
                .target(name: macosApp.name, path: project.path): Set(),
                .target(name: tvosApp.name, path: project.path): Set(),
                .target(name: framework.name, path: project.path): Set(),
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.apps()

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got.contains(GraphTarget(path: project.path, target: macosApp, project: project)))
        XCTAssertTrue(got.contains(GraphTarget(path: project.path, target: tvosApp, project: project)))
    }

    func test_allTargets_returns_all_the_targets() {
        // Given
        let firstPath = try! AbsolutePath(validating: "/first")
        let firstProject = Project.test(path: firstPath)
        let secondPath = try! AbsolutePath(validating: "/second")
        let secondProject = Project.test(path: secondPath)
        let firstTarget = Target.test(name: "first")
        let secondTarget = Target.test(name: "second")
        let graph = Graph.test(
            projects: [
                firstPath: firstProject,
                secondPath: secondProject,
            ],
            targets: [
                firstPath: [firstTarget.name: firstTarget],
                secondPath: [secondTarget.name: secondTarget],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = graphTraverser.allTargets().sorted()

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first?.project, firstProject)
        XCTAssertEqual(got.first?.target, firstTarget)
        XCTAssertEqual(got.last?.project, secondProject)
        XCTAssertEqual(got.last?.target, secondTarget)
    }

    func test_hasRemotePackages_when_has_remotePackages() {
        // Given
        let path = try! AbsolutePath(validating: "/project")
        let package = Package.remote(url: "https://git.tuist.io", requirement: .branch("main"))
        let graph = Graph.test(
            packages: [path: ["Test": package]],
            dependencies: [.packageProduct(path: path, product: "Test"): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        XCTAssertTrue(graphTraverser.hasRemotePackages)
    }

    func test_hasRemotePackages_when_doesnt_have_remove_packages() {
        // Given
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        XCTAssertFalse(graphTraverser.hasRemotePackages)
    }

    func test_extensionKitExtensionDependencies_when_dependencyIsExtensionKitExtension() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let extensionKitExtension = Target.test(name: "ExtensionKitExtension", product: .extensionKitExtension)
        let project = Project.test(targets: [app, extensionKitExtension])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set([.target(name: extensionKitExtension.name, path: project.path)]),
            .target(name: extensionKitExtension.name, path: project.path): Set([]),
        ]

        // Given: Value Graph
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                extensionKitExtension.name: extensionKitExtension,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.extensionKitExtensionDependencies(path: project.path, name: app.name).sorted()

        // Then
        XCTAssertEqual(got.map(\.target.name), [
            "ExtensionKitExtension",
        ])
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
