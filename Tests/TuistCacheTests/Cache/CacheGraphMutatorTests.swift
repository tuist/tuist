import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XCTest
@testable import TuistCache
@testable import TuistCoreTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

// To generate the ASCII graphs: http://asciiflow.com/
// Alternative: https://dot-to-ascii.ggerganov.com/
final class CacheGraphMutatorTests: TuistUnitTestCase {
    var xcframeworkLoader: MockXCFrameworkLoader!
    var frameworkLoader: MockFrameworkLoader!

    var subject: CacheGraphMutator!

    override func setUp() {
        super.setUp()
        xcframeworkLoader = MockXCFrameworkLoader()
        frameworkLoader = MockFrameworkLoader()
        subject = CacheGraphMutator(
            frameworkLoader: frameworkLoader,
            xcframeworkLoader: xcframeworkLoader
        )
    }

    override func tearDown() {
        super.tearDown()
        xcframeworkLoader = nil
        subject = nil
    }

    // First scenario
    //       +---->B (Cached XCFramework)+
    //       |                         |
    //    App|                         +------>D (Cached XCFramework)
    //       |                         |
    //       +---->C (Cached XCFramework)+
    func test_map_when_first_scenario() throws {
        let path = try temporaryPath()

        // Given: D
        let dFramework = Target.test(name: "D", platform: .iOS, product: .framework)
        let dProject = Project.test(path: path.appending(component: "D"), name: "D", targets: [dFramework])
        let dFrameworkGraphTarget = ValueGraphTarget.test(path: dProject.path, target: dFramework, project: dProject)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [app])
        let appTargetGraphTarget = ValueGraphTarget.test(path: appProject.path, target: app, project: appProject)

        let graphTargets = [bFrameworkGraphTarget, cFrameworkGraphTarget, dFrameworkGraphTarget, appTargetGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let dXCFramework = ValueGraphDependency.testXCFramework(path: dXCFrameworkPath)
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = ValueGraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = ValueGraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            dFrameworkGraphTarget: dXCFrameworkPath,
            bFrameworkGraphTarget: bXCFrameworkPath,
            cFrameworkGraphTarget: cXCFrameworkPath,
        ]

        xcframeworkLoader.loadStub = { path in
            if path == dXCFrameworkPath { return dXCFramework }
            else if path == bXCFrameworkPath { return bXCFramework }
            else if path == cXCFrameworkPath { return cXCFramework }
            else { fatalError("Unexpected load call") }
        }

        frameworkLoader.loadStub = { _ in
            throw "Can't find .framework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
            dependencies: [
                .testXCFramework(path: bXCFrameworkPath): [
                    .testXCFramework(path: dXCFrameworkPath),
                ],
                .testXCFramework(path: cXCFrameworkPath): [
                    .testXCFramework(path: dXCFrameworkPath),
                ],
                .target(name: app.name, path: appTargetGraphTarget.path): [
                    .testXCFramework(path: bXCFrameworkPath),
                    .testXCFramework(path: cXCFrameworkPath),
                ],
            ]
        )

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // Second scenario
    //       +---->B (Cached XCFramework)+
    //       |                         |
    //    App|                         +------>D Precompiled .framework
    //       |                         |
    //       +---->C (Cached XCFramework)+
    func test_map_when_second_scenario() throws {
        let path = try temporaryPath()

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: appTarget, project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let bXCFramework = ValueGraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = ValueGraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            bGraphTarget: bXCFrameworkPath,
            cGraphTarget: cXCFrameworkPath,
        ]

        xcframeworkLoader.loadStub = { path in
            if path == bXCFrameworkPath { return bXCFramework }
            else if path == cXCFrameworkPath { return cXCFramework }
            else { fatalError("Unexpected load call") }
        }

        frameworkLoader.loadStub = { path in
            if path == dFrameworkPath { return dFramework }
            throw "Can't find .framework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // Third scenario
    //       +---->B (Cached XCFramework)+
    //       |                         |
    //    App|                         +------>D Precompiled .framework
    //       |                         |
    //       +---->C (Cached XCFramework)+------>E Precompiled .xcframework
    func test_map_when_third_scenario() throws {
        let path = try temporaryPath()

        // Given nodes

        // Given E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = ValueGraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: appTarget, project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let bXCFramework = ValueGraphDependency.testXCFramework(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = ValueGraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            bGraphTarget: bXCFrameworkPath,
            cGraphTarget: cXCFrameworkPath,
        ]

        xcframeworkLoader.loadStub = { path in
            if path == bXCFrameworkPath { return bXCFramework }
            else if path == cXCFrameworkPath { return cXCFramework }
            else { fatalError("Unexpected load call") }
        }

        frameworkLoader.loadStub = { path in
            if path == dFrameworkPath { return dFramework }
            throw "Can't find .framework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // Fourth scenario
    //       +---->B (Framework)+------>D Precompiled .framework
    //       |
    //    App|
    //       |
    //       +---->C (Cached XCFramework)+------>E Precompiled .xcframework
    func test_map_when_fourth_scenario() throws {
        let path = try temporaryPath()

        // Given nodes

        // Given: E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = ValueGraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cProject = Project.test(path: path.appending(component: "C"), name: "C")
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTarget = ValueGraphTarget.test(
            path: appProject.path,
            target: Target.test(name: "App", platform: .iOS, product: .app),
            project: appProject
        )

        let graphTargets = [bGraphTarget, cGraphTarget, appTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .target(name: cFramework.name, path: cGraphTarget.path): [
                    eXCFramework,
                ],
                .target(name: appTarget.target.name, path: appTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )

        // Given xcframeworks
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = ValueGraphDependency.testXCFramework(path: cXCFrameworkPath)
        let xcframeworks = [
            cGraphTarget: cXCFrameworkPath,
        ]

        xcframeworkLoader.loadStub = { path in
            if path == cXCFrameworkPath { return cXCFramework }
            else { fatalError("Unexpected load call") }
        }

        frameworkLoader.loadStub = { path in
            if path == dFrameworkPath { return dFramework }
            throw "Can't find .framework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    dFramework,
                ],
                .testXCFramework(path: cXCFrameworkPath): [
                    eXCFramework,
                ],
                .target(name: appTarget.target.name, path: appTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                    .testXCFramework(path: cXCFrameworkPath),
                ],
            ]
        )

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got.dependencies,
            expectedGraph.dependencies
        )
    }

    // Fifth scenario
    //
    //    App ---->B (Framework)+------>C (Framework that depends on XCTest)
    func test_map_when_fith_scenario() throws {
        let path = try temporaryPath()

        // Given nodes
        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appGraphTarget = ValueGraphTarget.test(
            path: appProject.path,
            target: Target.test(name: "App", platform: .iOS, product: .app),
            project: appProject
        )

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: [:], sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            graph
        )
    }

    /// Scenario with cached .framework

    // Sixth scenario
    //       +---->B (Cached Framework)+
    //       |                         |
    //    App|                         +------>D (Cached Framework)
    //       |                         |
    //       +---->C (Cached Framework)+
    func test_map_when_sixth_scenario() throws {
        let path = try temporaryPath()

        // Given: D
        let dFramework = Target.test(name: "D", platform: .iOS, product: .framework)
        let dProject = Project.test(path: path.appending(component: "D"), name: "D", targets: [dFramework])
        let dGraphTarget = ValueGraphTarget.test(path: dProject.path, target: dFramework, project: dProject)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: appTarget, project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, dGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let dCachedFramework = ValueGraphDependency.testFramework(path: dCachedFrameworkPath)
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = ValueGraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = ValueGraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            dGraphTarget: dCachedFrameworkPath,
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        frameworkLoader.loadStub = { path in
            if path == dCachedFrameworkPath { return dCachedFramework }
            else if path == bCachedFrameworkPath { return bCachedFramework }
            else if path == cCachedFrameworkPath { return cCachedFramework }
            else { fatalError("Unexpected load call") }
        }

        xcframeworkLoader.loadStub = { _ in
            throw "Can't find an .xcframework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
            dependencies: [
                .testFramework(path: bCachedFrameworkPath): [
                    .testFramework(path: dCachedFrameworkPath),
                ],
                .testFramework(path: cCachedFrameworkPath): [
                    .testFramework(path: dCachedFrameworkPath),
                ],
                .target(name: appTarget.name, path: appGraphTarget.path): [
                    .testFramework(path: bCachedFrameworkPath),
                    .testFramework(path: cCachedFrameworkPath),
                ],
            ]
        )

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // Seventh scenario
    //       +---->B (Cached Framework)+
    //       |                         |
    //    App|                         +------>D Precompiled .framework
    //       |                         |
    //       +---->C (Cached Framework)+
    func test_map_when_seventh_scenario() throws {
        let path = try temporaryPath()

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: appTarget, project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let bCachedFramework = ValueGraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = ValueGraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        frameworkLoader.loadStub = { path in
            if path == bCachedFrameworkPath { return bCachedFramework }
            else if path == cCachedFrameworkPath { return cCachedFramework }
            else if path == dFrameworkPath { return dFramework }
            else { fatalError("Unexpected load call") }
        }

        xcframeworkLoader.loadStub = { _ in
            throw "Can't find .framework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // Eighth scenario
    //       +---->B (Cached Framework)+
    //       |                         |
    //    App|                         +------>D Precompiled .framework
    //       |                         |
    //       +---->C (Cached Framework)+------>E Precompiled .xcframework
    func test_map_when_eighth_scenario() throws {
        let path = try temporaryPath()

        // Given nodes

        // Given E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = ValueGraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: appTarget, project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let bCachedFramework = ValueGraphDependency.testFramework(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = ValueGraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            bGraphTarget: bCachedFrameworkPath,
            cGraphTarget: cCachedFrameworkPath,
        ]

        frameworkLoader.loadStub = { path in
            if path == bCachedFrameworkPath { return bCachedFramework }
            else if path == cCachedFrameworkPath { return cCachedFramework }
            else if path == dFrameworkPath { return dFramework }
            else { fatalError("Unexpected load call") }
        }

        xcframeworkLoader.loadStub = { path in
            if path == eXCFrameworkPath { return eXCFramework }
            throw "Can't find an .xcframework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
    }

    // 9th scenario
    //       +---->B (Framework)+------>D Precompiled .framework
    //       |
    //    App|
    //       |
    //       +---->C (Cached Framework)+------>E Precompiled .xcframework
    func test_map_when_nineth_scenario() throws {
        let path = try temporaryPath()

        // Given nodes

        // Given: E
        let eXCFrameworkPath = path.appending(component: "E.xcframework")
        let eXCFramework = ValueGraphDependency.testXCFramework(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = ValueGraphDependency.testFramework(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bGraphTarget = ValueGraphTarget.test(path: bProject.path, target: bFramework, project: bProject)

        // Given: C
        let cProject = Project.test(path: path.appending(component: "C"), name: "C")
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = ValueGraphTarget.test(path: cProject.path, target: cFramework, project: cProject)

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appGraphTarget = ValueGraphTarget.test(path: appProject.path, target: Target.test(name: "App", platform: .iOS, product: .app), project: appProject)

        let graphTargets = [bGraphTarget, cGraphTarget, appGraphTarget]
        let graph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let cCachedFramework = ValueGraphDependency.testFramework(path: cCachedFrameworkPath)
        let frameworks = [
            cGraphTarget: cCachedFrameworkPath,
        ]

        frameworkLoader.loadStub = { path in
            if path == cCachedFrameworkPath { return cCachedFramework }
            else { fatalError("Unexpected load call") }
        }

        xcframeworkLoader.loadStub = { _ in
            throw "Can't find an .xcframework here"
        }

        let expectedGraph = ValueGraph.test(
            projects: graphProjects(graphTargets),
            targets: self.graphTargets(graphTargets),
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
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        XCTAssertEqual(
            got,
            expectedGraph
        )
//        let app = try XCTUnwrap(got.entryNodes.first as? ValueGraphTarget)
//        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? ValueGraphTarget }.first(where: { $0.name == "B" }))
//        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? GraphTarget }.first(where: { $0.path == cCachedFrameworkPath }))
//        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
    }

    fileprivate func graphProjects(_ targets: [ValueGraphTarget]) -> [AbsolutePath: Project] {
        targets.reduce(into: [AbsolutePath: Project]()) { acc, target in
            acc[target.project.path] = target.project
        }
    }

    fileprivate func graphTargets(_ targets: [ValueGraphTarget]) -> [AbsolutePath: [String: Target]] {
        targets.reduce(into: [AbsolutePath: [String: Target]]()) { acc, target in
            var targets = acc[target.path, default: [:]]
            targets[target.target.name] = target.target
            acc[target.path] = targets
        }
    }
}
