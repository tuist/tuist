import Foundation
import Path
import TuistCore
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

// To generate the ASCII graphs: http://asciiflow.com/
// Alternative: https://dot-to-ascii.ggerganov.com/
final class CacheGraphMutatorTests: TuistUnitTestCase {
    var artifactLoader: MockArtifactLoader!

    var subject: CacheGraphMutator!

    override func setUp() {
        super.setUp()
        artifactLoader = MockArtifactLoader()
        subject = CacheGraphMutator(
            artifactLoader: artifactLoader
        )
    }

    override func tearDown() {
        artifactLoader = nil
        subject = nil
        super.tearDown()
    }

    /// First scenario
    ///       +---->B (Cached XCFramework)+
    ///       |                         |
    ///    App|                         +------>D (Cached XCFramework)
    ///       |                         |
    ///       +---->C (Cached XCFramework)+
    func test_map_when_first_scenario() async throws {
        let path = try temporaryPath()

        // Given: D
        let dFramework = Target.test(name: "D", platform: .iOS, product: .framework)
        let dProject = Project.test(
            path: path.appending(component: "D"), name: "D", targets: [dFramework]
        )
        let dFrameworkGraphTarget = GraphTarget.test(
            path: dProject.path, target: dFramework, project: dProject
        )

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bFrameworkGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cFrameworkGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [app]
        )
        let appTargetGraphTarget = GraphTarget.test(
            path: appProject.path, target: app, project: appProject
        )

        let graph = Graph.test(
            projects: [
                dProject.path: dProject,
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bFrameworkGraphTarget.path): [
                    .target(name: dFramework.name, path: dFrameworkGraphTarget.path),
                ],
                .target(name: cFramework.name, path: cFrameworkGraphTarget.path): [
                    .target(name: dFramework.name, path: dFrameworkGraphTarget.path),
                ],
                .target(name: app.name, path: appTargetGraphTarget.path): [
                    .target(name: bFramework.name, path: bFrameworkGraphTarget.path),
                    .target(name: cFramework.name, path: cFrameworkGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let dXCFrameworkPath = path.appending(component: "D.xcframework")
        let dXCFramework = GraphDependency.testXCFramework(path: dXCFrameworkPath)
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = GraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = GraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            dFrameworkGraphTarget: dXCFrameworkPath,
            bFrameworkGraphTarget: bXCFrameworkPath,
            cFrameworkGraphTarget: cXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == dXCFrameworkPath {
                return dXCFramework
            } else if path == bXCFrameworkPath {
                return bXCFramework
            } else if path == cXCFrameworkPath {
                return cXCFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        let bDependencies = got.dependencies[
            .testXCFramework(path: bXCFrameworkPath), default: Set()
        ]
        XCTAssertEqual(
            bDependencies,
            [
                .testXCFramework(path: dXCFrameworkPath),
            ]
        )
        let cDependencies = got.dependencies[
            .testXCFramework(path: cXCFrameworkPath), default: Set()
        ]
        XCTAssertEqual(
            cDependencies,
            [
                .testXCFramework(path: dXCFrameworkPath),
            ]
        )
        let appDependencies = got.dependencies[
            .target(name: app.name, path: appTargetGraphTarget.path), default: Set()
        ]
        XCTAssertEqual(
            appDependencies,
            [
                .testXCFramework(path: bXCFrameworkPath),
                .testXCFramework(path: cXCFrameworkPath),
            ]
        )
    }

    /// Second scenario
    ///       +---->B (Cached XCFramework)+
    ///       |                         |
    ///    App|                         +------>D Precompiled .framework
    ///       |                         |
    ///       +---->C (Cached XCFramework)+
    func test_map_when_second_scenario() async throws {
        let path = try temporaryPath()

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path, target: appTarget, project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    dFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = GraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = GraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            bGraphTarget: bXCFrameworkPath,
            cGraphTarget: cXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == bXCFrameworkPath {
                return bXCFramework
            } else if path == cXCFrameworkPath {
                return cXCFramework
            } else if path == dFrameworkPath {
                return dFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .testXCFramework(path: bXCFrameworkPath): [
                    dFramework,
                ],
                .testXCFramework(path: cXCFrameworkPath): [
                    dFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .testXCFramework(path: bXCFrameworkPath),
                    .testXCFramework(path: cXCFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    /// Third scenario
    ///       +---->B (Cached XCFramework)+
    ///       |                         |
    ///    App|                         +------>D Precompiled .framework
    ///       |                         |
    ///       +---->C (Cached XCFramework)+------>E Precompiled .xcframework
    func test_map_when_third_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes

        // Given E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = GraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path, target: appTarget, project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    dFramework,
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = GraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = GraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            bGraphTarget: bXCFrameworkPath,
            cGraphTarget: cXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == bXCFrameworkPath {
                return bXCFramework
            } else if path == cXCFrameworkPath {
                return cXCFramework
            } else if path == dFrameworkPath {
                return dFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .testXCFramework(path: bXCFrameworkPath): [
                    dFramework,
                ],
                .testXCFramework(path: cXCFrameworkPath): [
                    dFramework,
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .testXCFramework(path: bXCFrameworkPath),
                    .testXCFramework(path: cXCFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    /// Fourth scenario
    ///       +---->B (Framework)+------>D Precompiled .framework
    ///       |
    ///    App|
    ///       |
    ///       +---->C (Cached XCFramework)+------>E Precompiled .xcframework
    func test_map_when_fourth_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes

        // Given: E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = GraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path,
            target: appTarget,
            project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = GraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            cGraphTarget: cXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == cXCFrameworkPath {
                return cXCFramework
            } else if path == dFrameworkPath {
                return dFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .testXCFramework(path: cXCFrameworkPath): [
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .testXCFramework(path: cXCFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got.dependencies,
            expectedGraph.dependencies
        )
    }

    /// Fifth scenario
    ///
    ///    App ---->B (Framework)+------>C (Framework that depends on XCTest)
    func test_map_when_fith_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes
        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appGraphTarget = GraphTarget.test(
            path: appProject.path,
            target: Target.test(name: "App", platform: .iOS, product: .app),
            project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    .testSDK(name: "XCTest"),
                ],
                .target(name: appGraphTarget.target.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: [:], sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            graph
        )
    }

    // Scenario with cached .framework

    /// Sixth scenario
    ///       +---->B (Cached Framework)+
    ///       |                         |
    ///    App|                         +------>D (Cached Framework)
    ///       |                         |
    ///       +---->C (Cached Framework)+
    func test_map_when_sixth_scenario() async throws {
        let path = try temporaryPath()

        // Given: D
        let dFramework = Target.test(name: "D", platform: .iOS, product: .framework)
        let dProject = Project.test(
            path: path.appending(component: "D"), name: "D", targets: [dFramework]
        )
        let dGraphTarget = GraphTarget.test(
            path: dProject.path, target: dFramework, project: dProject
        )

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path, target: appTarget, project: appProject
        )

        let graph = Graph.test(
            projects: [
                dProject.path: dProject,
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: dFramework.name, path: dGraphTarget.path),
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    .target(name: dFramework.name, path: dGraphTarget.path),
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let dCachedFrameworkPath = path.appending(component: "D.framework")
        let dCachedFramework = GraphDependency.testFramework(path: dCachedFrameworkPath)
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = GraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = GraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            dGraphTarget: dCachedFrameworkPath,
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == dCachedFrameworkPath {
                return dCachedFramework
            } else if path == bCachedFrameworkPath {
                return bCachedFramework
            } else if path == cCachedFrameworkPath {
                return cCachedFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        let bDependencies = got.dependencies[
            .testFramework(path: bCachedFrameworkPath), default: Set()
        ]
        XCTAssertEqual(
            bDependencies,
            [
                .testFramework(path: dCachedFrameworkPath),
            ]
        )
        let cDependencies = got.dependencies[
            .testFramework(path: cCachedFrameworkPath), default: Set()
        ]
        XCTAssertEqual(
            cDependencies,
            [
                .testFramework(path: dCachedFrameworkPath),
            ]
        )
        let appDependencies = got.dependencies[
            .target(name: appTarget.name, path: appGraphTarget.path), default: Set()
        ]
        XCTAssertEqual(
            appDependencies,
            [
                .testFramework(path: bCachedFrameworkPath),
                .testFramework(path: cCachedFrameworkPath),
            ]
        )
    }

    /// Seventh scenario
    ///       +---->B (Cached Framework)+
    ///       |                         |
    ///    App|                         +------>D Precompiled .framework
    ///       |                         |
    ///       +---->C (Cached Framework)+
    func test_map_when_seventh_scenario() async throws {
        let path = try temporaryPath()

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path, target: appTarget, project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    dFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = GraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = GraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == bCachedFrameworkPath {
                return bCachedFramework
            } else if path == cCachedFrameworkPath {
                return cCachedFramework
            } else if path == dFrameworkPath {
                return dFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .testFramework(path: bCachedFrameworkPath): [
                    dFramework,
                ],
                .testFramework(path: cCachedFrameworkPath): [
                    dFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .testFramework(path: bCachedFrameworkPath),
                    .testFramework(path: cCachedFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    /// Eighth scenario
    ///       +---->B (Cached Framework)+
    ///       |                         |
    ///    App|                         +------>D Precompiled .framework
    ///       |                         |
    ///       +---->C (Cached Framework)+------>E Precompiled .xcframework
    func test_map_when_eighth_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes

        // Given E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = GraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path, target: appTarget, project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    dFramework,
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = GraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = GraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == bCachedFrameworkPath {
                return bCachedFramework
            } else if path == cCachedFrameworkPath {
                return cCachedFramework
            } else if path == dFrameworkPath {
                return dFramework
            } else if path == eXCFrameworkPath {
                return eXCFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .testFramework(path: bCachedFrameworkPath): [
                    dFramework,
                ],
                .testFramework(path: cCachedFrameworkPath): [
                    dFramework,
                    eXCFramework,
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .testFramework(path: bCachedFrameworkPath),
                    .testFramework(path: cCachedFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    /// 9th scenario
    ///       +---->B (Framework)+------>D Precompiled .framework
    ///       |
    ///    App|
    ///       |
    ///       +---->C (Cached Framework)+------>E Precompiled .xcframework
    func test_map_when_nineth_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes

        // Given: E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = GraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = GraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(
            path: path.appending(component: "C"), name: "C", targets: [cFramework]
        )
        let cGraphTarget = GraphTarget.test(
            path: cProject.path, target: cFramework, project: cProject
        )

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path,
            target: appTarget,
            project: appProject
        )

        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    eXCFramework,
                ],
                .target(name: appGraphTarget.target.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let cCachedFrameworkPath = path.appending(component: "C.xcframework")
        let cCachedFramework = GraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            cGraphTarget: cCachedFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == cCachedFrameworkPath {
                return cCachedFramework
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                cProject.path: cProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .testFramework(path: cCachedFrameworkPath): [
                    eXCFramework,
                ],
                .target(name: appGraphTarget.target.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .testFramework(path: cCachedFrameworkPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    /// Ninth scenario
    ///
    ///    App+----->B (Cached Framework)+--(macOS condition)---->C Precompiled .framework
    func test_map_when_ninth_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes

        // Given: App
        let appTarget = Target.test(
            name: "App", destinations: [.iPad, .iPhone, .appleTv, .mac], product: .app
        )
        let appProject = Project.test(
            path: path.appending(component: "App"), name: "App", targets: [appTarget]
        )
        let appGraphTarget = GraphTarget.test(
            path: appProject.path,
            target: appTarget,
            project: appProject
        )

        // Given: B
        let bFramework = Target.test(
            name: "B", destinations: [.iPad, .iPhone, .appleTv, .mac], product: .framework
        )
        let bProject = Project.test(
            path: path.appending(component: "B"), name: "B", targets: [bFramework]
        )
        let bGraphTarget = GraphTarget.test(
            path: bProject.path, target: bFramework, project: bProject
        )

        // Given: C
        let cFrameworkPath = path.appending(component: "C.framework")
        let cFramework = GraphDependency.testFramework(path: cFrameworkPath)

        // Given Graph
        let graph = Graph.test(
            projects: [
                bProject.path: bProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    cFramework,
                ],
            ],
            dependencyConditions: [
                GraphEdge(
                    from: .target(name: bFramework.name, path: bGraphTarget.path), to: cFramework
                ):
                    .when(Set([.ios]))!,
            ]
        )

        // Given xcframeworks
        let bFrameworkPath = path.appending(component: "C.xcframework")
        let frameworks = [
            GraphTarget(path: bProject.path, target: bFramework, project: bProject): bFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == bFrameworkPath {
                return GraphDependency.testFramework(path: bFrameworkPath)
            } else {
                fatalError("Unexpected load call")
            }
        }

        let expectedGraph = Graph.test(
            projects: [
                bProject.path: bProject,
                appProject.path: appProject,
            ],
            dependencies: [
                .target(name: appTarget.name, path: appProject.path): [
                    GraphDependency.testFramework(path: bFrameworkPath),
                ],
                GraphDependency.testFramework(path: bFrameworkPath): [
                    cFramework,
                ],
            ],
            dependencyConditions: [
                GraphEdge(
                    from: GraphDependency.testFramework(path: bFrameworkPath), to: cFramework
                ):
                    .when(Set([.ios]))!,
            ]
        )

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got.dependencies,
            expectedGraph.dependencies
        )
        XCTAssertEqual(
            got.dependencyConditions,
            expectedGraph.dependencyConditions
        )
    }

    ///            Cached        Cached
    /// ┌───┐    ┌────────┐     ┌──────┐
    /// │App├────► MacroB ├─────►MacroC│
    /// └───┘    └────┬───┘     └───┬──┘
    ///               │             │
    ///          ┌────▼───┐     ┌───▼──┐
    ///          │  Macro │     │ Macro│
    ///          └────────┘     └──────┘
    func test_map_when_tenth_scenario() async throws {
        // TODO: Adjust with the new macro mutation logic
        //        let path = try temporaryPath()
        //
        //        // Given nodes
        //
        //        // Given: App
        //        let project = Project.test(path: path.appending(component: "App"), name: "App")
        //        let app = Target.test(name: "App", destinations: [.iPad, .iPhone, .appleTv, .mac], product: .app)
        //        let appGraphTarget = GraphTarget.test(path: project.path, target: app, project: project)
        //        let swiftSyntax = Target.test(
        //            name: "SwiftSyntax",
        //            destinations: [.iPad, .iPhone, .appleTv, .mac],
        //            product: .staticLibrary
        //        )
        //        let swiftSyntaxGraphTarget = GraphTarget.test(path: project.path, target: swiftSyntax, project: project)
        //
        //        // Given: B
        //        let bMacroFramework = Target.test(
        //            name: "BMacro",
        //            destinations: [.iPad, .iPhone, .appleTv, .mac],
        //            product: .staticFramework
        //        )
        //        let bMacroExecutable = Target.test(name: "BExecutable", destinations: [.iPad, .iPhone, .appleTv, .mac], product:
        //        .macro)
        //        let bMacroFrameworkGraphTarget = GraphTarget.test(path: project.path, target: bMacroFramework, project: project)
        //        let bMacroExecutableGraphTarget = GraphTarget.test(path: project.path, target: bMacroExecutable, project:
        //        project)
        //
        //        // Given: C
        //        let cMacroFramework = Target.test(
        //            name: "CMacro",
        //            destinations: [.iPad, .iPhone, .appleTv, .mac],
        //            product: .staticFramework
        //        )
        //        let cMacroExecutable = Target.test(name: "CExecutable", destinations: [.iPad, .iPhone, .appleTv, .mac], product:
        //        .macro)
        //        let cMacroFrameworkGraphTarget = GraphTarget.test(path: project.path, target: cMacroFramework, project: project)
        //        let cMacroExecutableGraphTarget = GraphTarget.test(path: project.path, target: cMacroExecutable, project:
        //        project)
        //
        //        // Given: Graph
        //        let graphTargets = [
        //            appGraphTarget,
        //            swiftSyntaxGraphTarget,
        //            bMacroFrameworkGraphTarget,
        //            bMacroExecutableGraphTarget,
        //            cMacroFrameworkGraphTarget,
        //            cMacroExecutableGraphTarget,
        //        ]
        //        let graph = Graph.test(
        //            projects: graphProjects(graphTargets),
        //            targets: self.graphTargets(graphTargets),
        //            dependencies: [
        //                .target(name: app.name, path: project.path): [
        //                    .target(name: bMacroFramework.name, path: project.path),
        //                ],
        //                .target(name: bMacroFramework.name, path: project.path): [
        //                    .target(name: cMacroFramework.name, path: project.path),
        //                    .target(name: bMacroExecutable.name, path: project.path),
        //                ],
        //                .target(name: cMacroFramework.name, path: project.path): [
        //                    .target(name: cMacroExecutable.name, path: project.path),
        //                ],
        //                .target(name: bMacroExecutable.name, path: project.path): [
        //                    .target(name: swiftSyntax.name, path: project.path),
        //                ],
        //                .target(name: cMacroExecutable.name, path: project.path): [
        //                    .target(name: swiftSyntax.name, path: project.path),
        //                ],
        //            ]
        //        )
        //
        //        // Given xcframeworks
        //        let bMacroXCFrameworkPath = path.appending(component: "BMacroFramework.xcframework")
        //        let cMacroXCFrameworkPath = path.appending(component: "CMacroFramework.xcframework")
        //        let frameworks = [
        //            bMacroFrameworkGraphTarget: bMacroXCFrameworkPath,
        //            cMacroFrameworkGraphTarget: cMacroXCFrameworkPath,
        //        ]
        //
        //        artifactLoader.loadStub = { path in
        //            if path == bMacroXCFrameworkPath { return GraphDependency.testFramework(path: bMacroXCFrameworkPath) }
        //            if path == cMacroXCFrameworkPath { return GraphDependency.testFramework(path: cMacroXCFrameworkPath) }
        //            else { fatalError("Unexpected load call") }
        //        }
        //
        //        // When
        //        let got = try await subject.map(graph: graph, precompiledArtifacts: frameworks, sources: Set(["App"]))
        //
        //        // Then
        //        XCTAssertEqual(
        //            got.dependencies,
        //            [
        //                GraphDependency.testFramework(path: cMacroXCFrameworkPath): Set([]),
        //                GraphDependency
        //                    .testFramework(path: bMacroXCFrameworkPath): Set([
        //                        GraphDependency
        //                            .testFramework(path: cMacroXCFrameworkPath),
        //                    ]),
        //                .target(name: app.name, path: project.path): Set([GraphDependency.testFramework(path: bMacroXCFrameworkPath)]),
        //            ]
        //        )
    }

    ///          Not Cached
    /// ┌───┐    ┌────────┐     ┌──────┐
    /// │App├────► MacroB ├─────►Exec. │
    /// └───┘    └────┬───┘     └───┬──┘
    func test_map_when_eleventh_scenario() async throws {
        let path = try temporaryPath()

        // Given nodes
        let app = Target.test(
            name: "App", destinations: [.iPad, .iPhone, .appleTv, .mac], product: .app
        )
        let bMacroExecutable = Target.test(
            name: "BExecutable", destinations: [.iPad, .iPhone, .appleTv, .mac], product: .macro
        )
        let swiftSyntax = Target.test(
            name: "SwiftSyntax",
            destinations: [.iPad, .iPhone, .appleTv, .mac],
            product: .staticLibrary
        )
        let bMacroFramework = Target.test(
            name: "BMacro",
            destinations: [.iPad, .iPhone, .appleTv, .mac],
            product: .staticFramework
        )
        let project = Project.test(
            path: path.appending(component: "App"),
            name: "App",
            targets: [app, bMacroExecutable, swiftSyntax, bMacroFramework]
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: bMacroFramework.name, path: project.path),
                ],
                .target(name: bMacroFramework.name, path: project.path): [
                    .target(name: bMacroExecutable.name, path: project.path),
                ],
                .target(name: bMacroExecutable.name, path: project.path): [
                    .target(name: swiftSyntax.name, path: project.path),
                ],
            ]
        )

        artifactLoader.loadStub = { _ in
            fatalError("Unexpected load call")
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: [:], sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(got.dependencies, graph.dependencies)
    }

    ///               (Cached)           (Cached)
    /// ┌─────┐  ┌─────────────────┐ ┌──────────────┐
    /// │ App ├──►Dynamic framework├─►Static fram.  │
    /// └─────┘  └─────────────────┘ └──────────────┘
    func test_map_when_twelfth_scenario() async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let dynamicFramework = Target.test(
            name: "DynamicFramework", destinations: [.iPhone], product: .framework
        )
        let staticFramework = Target.test(
            name: "StaticLibrary", destinations: [.iPhone], product: .staticFramework
        )
        let project = Project.test(
            path: path.appending(component: "App"),
            name: "App",
            targets: [app, dynamicFramework, staticFramework]
        )
        let dynamicFrameworkGraphTarget = GraphTarget.test(
            path: project.path, target: dynamicFramework, project: project
        )
        let staticFrameworkGraphTarget = GraphTarget.test(
            path: project.path, target: staticFramework, project: project
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: dynamicFramework.name, path: project.path),
                ],
                .target(name: dynamicFramework.name, path: project.path): [
                    .target(name: staticFramework.name, path: project.path),
                ],
            ]
        )
        let dynamicXCFrameworkPath = path.appending(component: "Dynamic.xcframework")
        let staticXCFrameworkPath = path.appending(component: "Static.xcframework")
        let xcframeworks = [
            dynamicFrameworkGraphTarget: dynamicXCFrameworkPath,
            staticFrameworkGraphTarget: staticXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == dynamicXCFrameworkPath {
                return GraphDependency.testXCFramework(path: dynamicXCFrameworkPath)
            }
            if path == staticXCFrameworkPath {
                return GraphDependency.testXCFramework(path: staticXCFrameworkPath)
            } else {
                fatalError("Unexpected load call")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got.dependencies,
            [
                .testXCFramework(path: staticXCFrameworkPath): [],
                .target(name: app.name, path: project.path): [
                    .testXCFramework(path: dynamicXCFrameworkPath),
                ],
                .testXCFramework(path: dynamicXCFrameworkPath): [
                    .testXCFramework(path: staticXCFrameworkPath),
                ],
            ]
        )
    }

    ///                         (Cached)
    /// ┌─────┐  ┌─────────────────┐
    /// │ App ├──►  Dynamic framework (.none LinkingStatus)
    /// └─────┘  └─────────────────┘
    func test_map_when_thirteenth_scenario() async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let dynamicFramework = Target.test(
            name: "DynamicFramework", destinations: [.iPhone], product: .framework
        )
        let project = Project.test(
            path: path.appending(component: "App"),
            name: "App",
            targets: [app, dynamicFramework]
        )
        let dynamicFrameworkGraphTarget = GraphTarget.test(
            path: project.path, target: dynamicFramework, project: project
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: dynamicFramework.name, path: project.path, status: .none),
                ],
            ]
        )
        let dynamicXCFrameworkPath = path.appending(component: "Dynamic.xcframework")
        let xcframeworks = [
            dynamicFrameworkGraphTarget: dynamicXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == dynamicXCFrameworkPath {
                return GraphDependency.testXCFramework(path: dynamicXCFrameworkPath)
            } else {
                fatalError("Unexpected load call")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: false
        )

        // Then
        XCTAssertEqual(
            got.dependencies,
            [
                .target(name: app.name, path: project.path): [],
                .testXCFramework(path: dynamicXCFrameworkPath): [],
            ]
        )
    }

    ///                         (Cached)
    /// ┌─────┐  ┌─────────────────┐
    /// │ App ├──►  Dynamic framework (.none LinkingStatus)
    /// └─────┘  └─────────────────┘
    func test_map_when_thirteenth_scenario_with_keeping_source_targets() async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let dynamicFramework = Target.test(
            name: "DynamicFramework", destinations: [.iPhone], product: .framework
        )
        let project = Project.test(
            path: path.appending(component: "App"),
            name: "App",
            targets: [app, dynamicFramework]
        )
        let dynamicFrameworkGraphTarget = GraphTarget.test(
            path: project.path, target: dynamicFramework, project: project
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: dynamicFramework.name, path: project.path, status: .none),
                ],
            ]
        )
        let dynamicXCFrameworkPath = path.appending(component: "Dynamic.xcframework")
        let xcframeworks = [
            dynamicFrameworkGraphTarget: dynamicXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == dynamicXCFrameworkPath {
                return GraphDependency.testXCFramework(path: dynamicXCFrameworkPath)
            } else {
                fatalError("Unexpected load call")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["App"]),
            keepSourceTargets: true
        )

        // Then
        XCTAssertEqual(
            got.projects[project.path]?.targets.values.first(where: { $0.name == dynamicFramework.name })?.metadata.tags
                .contains("tuist:binary-sources"),
            true
        )
        XCTAssertEqual(
            got.dependencies,
            [
                .target(name: app.name, path: project.path): [],
                .target(name: dynamicFramework.name, path: project.path): [],
                .testXCFramework(path: dynamicXCFrameworkPath): [],
            ]
        )
    }

    ///           (Cached)  (Cached)  (Cached)
    /// ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐
    /// │ App           ├──► A          ├──► B          ├──► C         │
    /// └─────┘  └─────┘  └─────┘  └─────┘
    func test_map_when_fourteenth_scenario_with_keeping_source_targets() async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let a = Target.test(
            name: "A", destinations: [.iPhone], product: .framework
        )
        let b = Target.test(
            name: "B", destinations: [.iPhone], product: .framework
        )
        let c = Target.test(
            name: "C", destinations: [.iPhone], product: .framework
        )
        let project = Project.test(
            path: path.appending(component: "App"),
            name: "App",
            targets: [app, a, b, c]
        )
        let aGraphTarget = GraphTarget.test(
            path: project.path, target: a, project: project
        )
        let bGraphTarget = GraphTarget.test(
            path: project.path, target: b, project: project
        )
        let cGraphTarget = GraphTarget.test(
            path: project.path, target: c, project: project
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: a.name, path: project.path, status: .required),
                ],
                .target(name: a.name, path: project.path): [
                    .target(name: b.name, path: project.path, status: .required),
                ],
                .target(name: b.name, path: project.path): [
                    .target(name: c.name, path: project.path, status: .required),
                ],
            ]
        )
        let aXCFrameworkPath = path.appending(component: "A.xcframework")
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let xcframeworks = [
            aGraphTarget: aXCFrameworkPath,
            bGraphTarget: bXCFrameworkPath,
            cGraphTarget: cXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in GraphDependency.testXCFramework(path: path) }

        // When
        let got = try await subject.map(
            graph: graph, precompiledArtifacts: xcframeworks, sources: Set(["B"]),
            keepSourceTargets: true
        )

        XCTAssertEqual(
            got.dependencies,
            // Keeps the sources of all the targets.
            [
                .target(name: app.name, path: project.path): [.target(name: a.name, path: project.path)],
                .target(name: a.name, path: project.path): [.target(name: b.name, path: project.path)],
                .target(name: b.name, path: project.path): [.testXCFramework(path: cXCFrameworkPath)],
                .target(name: c.name, path: project.path): [],
                .testXCFramework(path: cXCFrameworkPath): [],
            ]
        )
    }

    /// Fifteenth scenario - reproduces https://github.com/tuist/tuist/issues/9594
    /// A unit test target depends on a dynamic framework that transitively depends
    /// on static libraries. When all are cached, the static dependencies should be
    /// pruned from the dynamic xcframework's edges to avoid duplicate symbols.
    ///
    /// ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
    /// │ SharedCounterTest├──►│ SharedCounter     ├──►│ TCALib (static)  │
    /// │ (unitTests)      │   │ (framework, dyn.) │   │ (staticFw, cached)│
    /// └──────────────────┘   └──────────────────┘   └────────┬─────────┘
    ///                                                         │
    ///                                                ┌────────▼─────────┐
    ///                                                │ DepLib (static)  │
    ///                                                │ (staticFw, cached)│
    ///                                                └──────────────────┘
    func test_map_when_unit_test_depends_on_cached_dynamic_framework_with_static_deps() async throws {
        let path = try temporaryPath()

        // Given: DepLib (static framework, cached)
        let depLib = Target.test(name: "DepLib", destinations: [.iPhone], product: .staticFramework)
        let depLibProject = Project.test(
            path: path.appending(component: "DepLib"), name: "DepLib", targets: [depLib]
        )
        let depLibGraphTarget = GraphTarget.test(
            path: depLibProject.path, target: depLib, project: depLibProject
        )

        // Given: TCALib (static framework, cached, depends on DepLib)
        let tcaLib = Target.test(name: "TCALib", destinations: [.iPhone], product: .staticFramework)
        let tcaLibProject = Project.test(
            path: path.appending(component: "TCALib"), name: "TCALib", targets: [tcaLib]
        )
        let tcaLibGraphTarget = GraphTarget.test(
            path: tcaLibProject.path, target: tcaLib, project: tcaLibProject
        )

        // Given: SharedCounter (dynamic framework, cached, depends on TCALib)
        let sharedCounter = Target.test(name: "SharedCounter", destinations: [.iPhone], product: .framework)
        let sharedCounterProject = Project.test(
            path: path.appending(component: "SharedCounter"), name: "SharedCounter", targets: [sharedCounter]
        )
        let sharedCounterGraphTarget = GraphTarget.test(
            path: sharedCounterProject.path, target: sharedCounter, project: sharedCounterProject
        )

        // Given: SharedCounterTests (unit tests, NOT cached)
        let tests = Target.test(name: "SharedCounterTests", destinations: [.iPhone], product: .unitTests)
        let testsProject = Project.test(
            path: path.appending(component: "Tests"), name: "Tests", targets: [tests]
        )
        let testsGraphTarget = GraphTarget.test(
            path: testsProject.path, target: tests, project: testsProject
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [
                depLibProject.path: depLibProject,
                tcaLibProject.path: tcaLibProject,
                sharedCounterProject.path: sharedCounterProject,
                testsProject.path: testsProject,
            ],
            dependencies: [
                .target(name: tests.name, path: testsGraphTarget.path): [
                    .target(name: sharedCounter.name, path: sharedCounterGraphTarget.path),
                ],
                .target(name: sharedCounter.name, path: sharedCounterGraphTarget.path): [
                    .target(name: tcaLib.name, path: tcaLibGraphTarget.path),
                ],
                .target(name: tcaLib.name, path: tcaLibGraphTarget.path): [
                    .target(name: depLib.name, path: depLibGraphTarget.path),
                ],
            ]
        )

        // Given: xcframeworks for all cacheable targets
        let depLibXCFrameworkPath = path.appending(component: "DepLib.xcframework")
        let tcaLibXCFrameworkPath = path.appending(component: "TCALib.xcframework")
        let sharedCounterXCFrameworkPath = path.appending(component: "SharedCounter.xcframework")

        let xcframeworks = [
            depLibGraphTarget: depLibXCFrameworkPath,
            tcaLibGraphTarget: tcaLibXCFrameworkPath,
            sharedCounterGraphTarget: sharedCounterXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == depLibXCFrameworkPath {
                return GraphDependency.testXCFramework(path: depLibXCFrameworkPath, linking: .static)
            } else if path == tcaLibXCFrameworkPath {
                return GraphDependency.testXCFramework(path: tcaLibXCFrameworkPath, linking: .static)
            } else if path == sharedCounterXCFrameworkPath {
                return GraphDependency.testXCFramework(path: sharedCounterXCFrameworkPath, linking: .dynamic)
            } else {
                fatalError("Unexpected load call for \(path)")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph,
            precompiledArtifacts: xcframeworks,
            sources: Set(["SharedCounterTests"]),
            keepSourceTargets: false
        )

        // Then: the test target should depend only on the dynamic xcframework.
        // The static xcframeworks (TCALib, DepLib) should NOT appear as deps of
        // SharedCounter.xcframework because they are baked into the dynamic binary.
        let testDependencies = got.dependencies[
            .target(name: tests.name, path: testsGraphTarget.path), default: Set()
        ]
        XCTAssertEqual(
            testDependencies,
            [
                .testXCFramework(path: sharedCounterXCFrameworkPath, linking: .dynamic),
            ]
        )

        let sharedCounterDeps = got.dependencies[
            .testXCFramework(path: sharedCounterXCFrameworkPath, linking: .dynamic), default: Set()
        ]
        XCTAssertEqual(
            sharedCounterDeps,
            [],
            "Dynamic xcframework should not have static deps as edges (they are baked in)"
        )

        // TCALib is a static framework so it does NOT bake in its static deps.
        // Its edge to DepLib should be preserved in the graph.
        let tcaLibDeps = got.dependencies[
            .testXCFramework(path: tcaLibXCFrameworkPath, linking: .static), default: Set()
        ]
        XCTAssertEqual(tcaLibDeps, [
            .testXCFramework(path: depLibXCFrameworkPath, linking: .static),
        ])

        let depLibDeps = got.dependencies[
            .testXCFramework(path: depLibXCFrameworkPath, linking: .static), default: Set()
        ]
        XCTAssertEqual(depLibDeps, [])
    }

    /// Sixteenth scenario - hostless unit tests still need external static xcframework deps
    /// to remain behind the cached dynamic xcframework for module visibility.
    ///
    /// ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────┐
    /// │ FeatureTests     ├──►│ Feature          ├──►│ GoogleMaps         │
    /// │ (unitTests)      │   │ (framework, dyn.)│   │ (static xcframework)│
    /// └──────────────────┘   └──────────────────┘   └────────────────────┘
    func test_map_when_unit_test_depends_on_cached_dynamic_framework_with_external_static_xcframework() async throws {
        let path = try temporaryPath()

        // Given: Feature (dynamic framework, cached, depends on GoogleMaps)
        let feature = Target.test(name: "Feature", destinations: [.iPhone], product: .framework)
        let featureProject = Project.test(
            path: path.appending(component: "Feature"), name: "Feature", targets: [feature]
        )
        let featureGraphTarget = GraphTarget.test(
            path: featureProject.path, target: feature, project: featureProject
        )

        // Given: FeatureTests (unit tests, NOT cached)
        let tests = Target.test(name: "FeatureTests", destinations: [.iPhone], product: .unitTests)
        let testsProject = Project.test(
            path: path.appending(component: "Tests"), name: "Tests", targets: [tests]
        )
        let testsGraphTarget = GraphTarget.test(
            path: testsProject.path, target: tests, project: testsProject
        )

        let googleMapsPath = path.appending(component: "GoogleMaps.xcframework")
        let googleMaps = GraphDependency.testXCFramework(
            path: googleMapsPath,
            linking: .static,
            moduleMaps: [
                googleMapsPath.appending(component: "GoogleMaps.modulemap"),
            ]
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [
                featureProject.path: featureProject,
                testsProject.path: testsProject,
            ],
            dependencies: [
                .target(name: tests.name, path: testsGraphTarget.path): [
                    .target(name: feature.name, path: featureGraphTarget.path),
                ],
                .target(name: feature.name, path: featureGraphTarget.path): [
                    googleMaps,
                ],
                googleMaps: [],
            ]
        )

        let featureXCFrameworkPath = path.appending(component: "Feature.xcframework")
        let xcframeworks = [
            featureGraphTarget: featureXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == featureXCFrameworkPath {
                return GraphDependency.testXCFramework(path: featureXCFrameworkPath, linking: .dynamic)
            } else {
                fatalError("Unexpected load call for \(path)")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph,
            precompiledArtifacts: xcframeworks,
            sources: Set(["FeatureTests"]),
            keepSourceTargets: false
        )

        // Then: external static xcframework deps should remain behind the cached dynamic binary.
        XCTAssertEqual(
            got.dependencies[
                .target(name: tests.name, path: testsGraphTarget.path),
                default: Set()
            ],
            [
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
                default: Set()
            ],
            [
                googleMaps,
            ]
        )
    }

    /// Seventeenth scenario - when a cached dynamic framework is shared between hostless tests
    /// and non-test targets, external static xcframework deps should stay on the dynamic node
    /// rather than being re-added directly to the app target.
    ///
    /// ┌─────┐              ┌──────────────────┐   ┌────────────────────┐
    /// │ App ├─────────────►│ Feature          ├──►│ GoogleMaps         │
    /// └─────┘              │ (framework, dyn.)│   │ (static xcframework)│
    /// ┌──────────────────┐ └──────────────────┘   └────────────────────┘
    /// │ FeatureTests     ├───────────────────────►
    /// │ (unitTests)      │
    /// └──────────────────┘
    func test_map_when_non_test_and_hostless_test_share_cached_dynamic_framework_with_external_static_xcframework(
    ) async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let feature = Target.test(name: "Feature", destinations: [.iPhone], product: .framework)
        let tests = Target.test(name: "FeatureTests", destinations: [.iPhone], product: .unitTests)
        let project = Project.test(
            path: path.appending(component: "Project"),
            name: "Project",
            targets: [app, feature, tests]
        )
        let featureGraphTarget = GraphTarget.test(
            path: project.path, target: feature, project: project
        )

        let googleMapsPath = path.appending(component: "GoogleMaps.xcframework")
        let googleMaps = GraphDependency.testXCFramework(
            path: googleMapsPath,
            linking: .static,
            moduleMaps: [
                googleMapsPath.appending(component: "GoogleMaps.modulemap"),
            ]
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: feature.name, path: project.path),
                ],
                .target(name: tests.name, path: project.path): [
                    .target(name: feature.name, path: project.path),
                ],
                .target(name: feature.name, path: project.path): [
                    googleMaps,
                ],
                googleMaps: [],
            ]
        )

        let featureXCFrameworkPath = path.appending(component: "Feature.xcframework")
        let xcframeworks = [
            featureGraphTarget: featureXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == featureXCFrameworkPath {
                return GraphDependency.testXCFramework(path: featureXCFrameworkPath, linking: .dynamic)
            } else {
                fatalError("Unexpected load call for \(path)")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph,
            precompiledArtifacts: xcframeworks,
            sources: Set(["App", "FeatureTests"]),
            keepSourceTargets: false
        )

        // Then: the app should keep depending only on the cached dynamic framework.
        XCTAssertEqual(
            got.dependencies[
                .target(name: app.name, path: project.path),
                default: Set()
            ],
            [
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .target(name: tests.name, path: project.path),
                default: Set()
            ],
            [
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
                default: Set()
            ],
            [
                googleMaps,
            ]
        )
    }

    /// Eighteenth scenario - preserve the current behaviour for cached static target deps that
    /// are baked into the shared dynamic xcframework but re-added to non-test consumers.
    ///
    /// ┌─────┐              ┌──────────────────┐   ┌──────────────────┐
    /// │ App ├─────────────►│ Feature          ├──►│ SupportLib       │
    /// └─────┘              │ (framework, dyn.)│   │ (static, cached) │
    /// ┌──────────────────┐ └──────────────────┘   └──────────────────┘
    /// │ FeatureTests     ├───────────────────────►
    /// │ (unitTests)      │
    /// └──────────────────┘
    func test_map_when_non_test_and_hostless_test_share_cached_dynamic_framework_with_cached_static_dep() async throws {
        let path = try temporaryPath()

        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let feature = Target.test(name: "Feature", destinations: [.iPhone], product: .framework)
        let supportLib = Target.test(name: "SupportLib", destinations: [.iPhone], product: .staticFramework)
        let tests = Target.test(name: "FeatureTests", destinations: [.iPhone], product: .unitTests)
        let project = Project.test(
            path: path.appending(component: "Project"),
            name: "Project",
            targets: [app, feature, supportLib, tests]
        )
        let featureGraphTarget = GraphTarget.test(
            path: project.path, target: feature, project: project
        )
        let supportLibGraphTarget = GraphTarget.test(
            path: project.path, target: supportLib, project: project
        )

        // Given: Graph
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: feature.name, path: project.path),
                ],
                .target(name: tests.name, path: project.path): [
                    .target(name: feature.name, path: project.path),
                ],
                .target(name: feature.name, path: project.path): [
                    .target(name: supportLib.name, path: project.path),
                ],
            ]
        )

        let featureXCFrameworkPath = path.appending(component: "Feature.xcframework")
        let supportLibXCFrameworkPath = path.appending(component: "SupportLib.xcframework")
        let xcframeworks = [
            featureGraphTarget: featureXCFrameworkPath,
            supportLibGraphTarget: supportLibXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == featureXCFrameworkPath {
                return GraphDependency.testXCFramework(path: featureXCFrameworkPath, linking: .dynamic)
            } else if path == supportLibXCFrameworkPath {
                return GraphDependency.testXCFramework(path: supportLibXCFrameworkPath, linking: .static)
            } else {
                fatalError("Unexpected load call for \(path)")
            }
        }

        // When
        let got = try await subject.map(
            graph: graph,
            precompiledArtifacts: xcframeworks,
            sources: Set(["App", "FeatureTests"]),
            keepSourceTargets: false
        )

        // Then: cached static deps remain pruned from the shared dynamic binary
        // and are re-added only to non-test consumers.
        XCTAssertEqual(
            got.dependencies[
                .target(name: app.name, path: project.path),
                default: Set()
            ],
            [
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
                .testXCFramework(path: supportLibXCFrameworkPath, linking: .static),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .target(name: tests.name, path: project.path),
                default: Set()
            ],
            [
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .testXCFramework(path: featureXCFrameworkPath, linking: .dynamic),
                default: Set()
            ],
            []
        )
    }

    /// Nineteenth scenario - a hostless test target explicitly imports a cached dynamic
    /// transitive dependency of a source dynamic framework. External static xcframework deps
    /// must remain behind the cached dynamic node rather than being re-added to the source framework.
    ///
    /// ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
    /// │ FeatureTests     ├──►│ Feature          ├──►│ Library          │
    /// │ (unitTests)      │   │ (framework, dyn.)│   │ (framework, dyn.)│
    /// └────────┬─────────┘   └──────────────────┘   └────────┬─────────┘
    ///          │                                              │
    ///          └──────────────────────────────────────────────►│
    ///                                                         ▼
    ///                                                ┌────────────────────┐
    ///                                                │ GoogleMaps         │
    ///                                                │ (static xcframework)│
    ///                                                └────────────────────┘
    func test_map_when_hostless_test_explicitly_imports_cached_dynamic_framework_with_external_static_xcframework(
    ) async throws {
        let path = try temporaryPath()

        let feature = Target.test(name: "Feature", destinations: [.iPhone], product: .framework)
        let library = Target.test(name: "Library", destinations: [.iPhone], product: .framework)
        let tests = Target.test(name: "FeatureTests", destinations: [.iPhone], product: .unitTests)
        let project = Project.test(
            path: path.appending(component: "Project"),
            name: "Project",
            targets: [feature, library, tests]
        )
        let libraryGraphTarget = GraphTarget.test(
            path: project.path, target: library, project: project
        )

        let googleMapsPath = path.appending(component: "GoogleMaps.xcframework")
        let googleMaps = GraphDependency.testXCFramework(
            path: googleMapsPath,
            linking: .static,
            moduleMaps: [
                googleMapsPath.appending(component: "GoogleMaps.modulemap"),
            ]
        )

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: feature.name, path: project.path): [
                    .target(name: library.name, path: project.path),
                ],
                .target(name: tests.name, path: project.path): [
                    .target(name: feature.name, path: project.path),
                    .target(name: library.name, path: project.path),
                ],
                .target(name: library.name, path: project.path): [
                    googleMaps,
                ],
                googleMaps: [],
            ]
        )

        let libraryXCFrameworkPath = path.appending(component: "Library.xcframework")
        let xcframeworks = [
            libraryGraphTarget: libraryXCFrameworkPath,
        ]

        artifactLoader.loadStub = { path in
            if path == libraryXCFrameworkPath {
                return GraphDependency.testXCFramework(path: libraryXCFrameworkPath, linking: .dynamic)
            } else {
                fatalError("Unexpected load call for \(path)")
            }
        }

        let got = try await subject.map(
            graph: graph,
            precompiledArtifacts: xcframeworks,
            sources: Set(["Feature", "FeatureTests"]),
            keepSourceTargets: false
        )

        XCTAssertEqual(
            got.dependencies[
                .target(name: feature.name, path: project.path),
                default: Set()
            ],
            [
                .testXCFramework(path: libraryXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .target(name: tests.name, path: project.path),
                default: Set()
            ],
            [
                .target(name: feature.name, path: project.path),
                .testXCFramework(path: libraryXCFrameworkPath, linking: .dynamic),
            ]
        )
        XCTAssertEqual(
            got.dependencies[
                .testXCFramework(path: libraryXCFrameworkPath, linking: .dynamic),
                default: Set()
            ],
            [
                googleMaps,
            ]
        )
    }
}

final class MockArtifactLoader: ArtifactLoading {
    var loadStub: ((AbsolutePath) throws -> GraphDependency)?
    func load(path: AbsolutePath) throws -> GraphDependency {
        if let loadStub {
            return try loadStub(path)
        } else {
            return GraphDependency.testFramework(path: path)
        }
    }
}
