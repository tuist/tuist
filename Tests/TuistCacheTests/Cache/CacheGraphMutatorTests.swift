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
final class CacheGraphMapperTests: TuistUnitTestCase {
    var xcframeworkLoader: MockXCFrameworkNodeLoader!
    var frameworkLoader: MockFrameworkNodeLoader!

    var subject: CacheGraphMutator!

    override func setUp() {
        xcframeworkLoader = MockXCFrameworkNodeLoader()
        frameworkLoader = MockFrameworkNodeLoader()
        subject = CacheGraphMutator(frameworkLoader: frameworkLoader,
                                    xcframeworkLoader: xcframeworkLoader)
        super.setUp()
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
        let dFrameworkNode = TargetNode.test(project: dProject, target: dFramework)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFrameworkNode])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFrameworkNode])

        // Given: App
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [app])
        let appTargetNode = TargetNode.test(project: appProject, target: app, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, dFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let dXCFrameworkPath = path.appending(component: "D.xcframework")
        let dXCFramework = XCFrameworkNode.test(path: dXCFrameworkPath)
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
        let xcframeworks = [
            dFrameworkNode: dXCFrameworkPath,
            bFrameworkNode: bXCFrameworkPath,
            cFrameworkNode: cXCFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        let appNode = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(appNode.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
        let c = try XCTUnwrap(appNode.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dXCFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dXCFrameworkPath }))
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
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFramework])

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appTargetNode = TargetNode.test(project: appProject, target: appTarget, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
        let xcframeworks = [
            bFrameworkNode: bXCFrameworkPath,
            cFrameworkNode: cXCFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
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
        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFramework, eXCFramework])

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appTargetNode = TargetNode.test(project: appProject, target: appTarget, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let bXCFrameworkPath = path.appending(component: "B.xcframework")
        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
        let xcframeworks = [
            bFrameworkNode: bXCFrameworkPath,
            cFrameworkNode: cXCFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
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
        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cProject = Project.test(path: path.appending(component: "C"), name: "C")
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [eXCFramework])

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTargetNode = TargetNode.test(project: appProject, target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
        let xcframeworks = [
            cFrameworkNode: cXCFrameworkPath,
        ]

        xcframeworkLoader.loadStub = { path in
            if path == cXCFrameworkPath { return cXCFramework }
            else { fatalError("Unexpected load call") }
        }

        frameworkLoader.loadStub = { path in
            if path == dFrameworkPath { return dFramework }
            throw "Can't find .framework here"
        }

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: xcframeworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0.name == "B" }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
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
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [SDKNode.xctest(platform: .iOS, status: .required)])

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [cFrameworkNode])

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTargetNode = TargetNode.test(project: appProject, target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: [:], sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0.name == "B" }))
        _ = try XCTUnwrap(b.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0.name == "C" }))
    }

    /// Scenari with cached .framework

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
        let dFrameworkNode = TargetNode.test(project: dProject, target: dFramework)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFrameworkNode])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFrameworkNode])

        // Given: App
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [app])
        let appTargetNode = TargetNode.test(project: appProject, target: app, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, dFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let dCachedFrameworkPath = path.appending(component: "D.framework")
        let dCachedFramework = FrameworkNode.test(path: dCachedFrameworkPath)
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = FrameworkNode.test(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = FrameworkNode.test(path: cCachedFrameworkPath)
        let frameworks = [
            dFrameworkNode: dCachedFrameworkPath,
            bFrameworkNode: bCachedFrameworkPath,
            cFrameworkNode: cCachedFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        let appNode = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(appNode.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == bCachedFrameworkPath }))
        let c = try XCTUnwrap(appNode.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == cCachedFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dCachedFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dCachedFrameworkPath }))
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
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFramework])

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appTargetNode = TargetNode.test(project: appProject, target: appTarget, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = FrameworkNode.test(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = FrameworkNode.test(path: cCachedFrameworkPath)
        let frameworks = [
            bFrameworkNode: bCachedFrameworkPath,
            cFrameworkNode: cCachedFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == bCachedFrameworkPath }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == cCachedFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
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
        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cProject = Project.test(path: path.appending(component: "C"), name: "C", targets: [cFramework])
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [dFramework, eXCFramework])

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appProject = Project.test(path: path.appending(component: "App"), name: "App", targets: [appTarget])
        let appTargetNode = TargetNode.test(project: appProject, target: appTarget, dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let bCachedFrameworkPath = path.appending(component: "B.framework")
        let bCachedFramework = FrameworkNode.test(path: bCachedFrameworkPath)
        let cCachedFrameworkPath = path.appending(component: "C.framework")
        let cCachedFramework = FrameworkNode.test(path: cCachedFrameworkPath)
        let frameworks = [
            bFrameworkNode: bCachedFrameworkPath,
            cFrameworkNode: cCachedFrameworkPath,
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

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == bCachedFrameworkPath }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == cCachedFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
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
        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)

        // Given: D
        let dFrameworkPath = path.appending(component: "D.framework")
        let dFramework = FrameworkNode.test(path: dFrameworkPath)

        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [dFramework])

        // Given: C
        let cProject = Project.test(path: path.appending(component: "C"), name: "C")
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cFrameworkNode = TargetNode.test(project: cProject, target: cFramework, dependencies: [eXCFramework])

        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTargetNode = TargetNode.test(project: appProject, target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFrameworkNode, cFrameworkNode])

        let targetNodes = [bFrameworkNode, cFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))

        // Given xcframeworks
        let cCachedFrameworkPath = path.appending(component: "C.xcframework")
        let cCachedFramework = FrameworkNode.test(path: cCachedFrameworkPath)
        let frameworks = [
            cFrameworkNode: cCachedFrameworkPath,
        ]

        frameworkLoader.loadStub = { path in
            if path == cCachedFrameworkPath { return cCachedFramework }
            else { fatalError("Unexpected load call") }
        }

        xcframeworkLoader.loadStub = { _ in
            throw "Can't find an .xcframework here"
        }

        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))

        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0.name == "B" }))
        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0.path == cCachedFrameworkPath }))
        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
    }
    
    // 10th scenario
    //       +---->B (Framework)
    //       |
    //    App|
    //       |
    //       +---->C (Bundle)
    func test_map_when_tenth_scenario() throws {
        let path = try temporaryPath()
        
        // Given nodes
        
        // Given: C
        let cBundle = TargetNode.test(target: .test(product: .bundle))
        
        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .staticFramework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [cBundle])
        
        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTargetNode = TargetNode.test(project: appProject, target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFrameworkNode])
        
        let targetNodes = [bFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))
                        
        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: [:], sources: Set(["App"]))
        
        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        _ = try XCTUnwrap(app.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0 == bFrameworkNode }))
        XCTAssertTrue(app.dependencies.contains(where: { $0 == cBundle }))
    }
    
    // 11th scenario
    //       +---->B (Cached Framework)
    //       |
    //    App|
    //       |
    //       +---->C (Bundle)
    func test_map_when_eleventh_scenario() throws {
        let path = try temporaryPath()
        
        // Given nodes
        
        // Given: C
        let cBundle = TargetNode.test(target: .test(product: .bundle))
        
        // Given: B
        let bFramework = Target.test(name: "B", platform: .iOS, product: .staticFramework)
        let bProject = Project.test(path: path.appending(component: "B"), name: "B", targets: [bFramework])
        let bFrameworkNode = TargetNode.test(project: bProject, target: bFramework, dependencies: [cBundle])
        
        // Given: App
        let appProject = Project.test(path: path.appending(component: "App"), name: "App")
        let appTargetNode = TargetNode.test(project: appProject, target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFrameworkNode])
        
        let targetNodes = [bFrameworkNode, appTargetNode]
        let graph = Graph.test(entryNodes: [appTargetNode], projects: graphProjects(targetNodes), targets: graphTargets(targetNodes))
        
        // Given xcframeworks
        let bCachedFrameworkPath = path.appending(component: "B.xcframework")
        let bCachedFramework = FrameworkNode.test(path: bCachedFrameworkPath)
        let frameworks = [
            bFrameworkNode: bCachedFrameworkPath,
        ]
        
        frameworkLoader.loadStub = { path in
            if path == bCachedFrameworkPath { return bCachedFramework }
            else { fatalError("Unexpected load call") }
        }
        
        xcframeworkLoader.loadStub = { _ in
            throw "Can't find an .xcframework here"
        }
        
        // When
        let got = try subject.map(graph: graph, precompiledFrameworks: frameworks, sources: Set(["App"]))
        
        // Then
        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
        _ = try XCTUnwrap(app.dependencies.compactMap { $0 as? FrameworkNode }.first(where: { $0 == bCachedFramework }))
        XCTAssertTrue(app.dependencies.contains(where: { $0 == cBundle }))
    }

    fileprivate func graphProjects(_ targets: [TargetNode]) -> [Project] {
        let projects = targets.reduce(into: Set<Project>()) { acc, target in
            acc.formUnion([target.project])
        }
        return Array(projects)
    }

    fileprivate func graphTargets(_ targets: [TargetNode]) -> [AbsolutePath: [TargetNode]] {
        targets.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, target in
            var targets = acc[target.path, default: []]
            targets.append(target)
            acc[target.path] = targets
        }
    }
}
