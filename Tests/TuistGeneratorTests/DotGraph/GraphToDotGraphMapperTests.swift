import Foundation
import GraphViz
import TSCBasic
import TuistCore
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class GraphToDotGraphMapperTests: XCTestCase {
    var subject: GraphToDotGraphMapper!

    override func setUp() {
        super.setUp()
        subject = GraphToDotGraphMapper()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
    }

    func test_map() throws {
        // Given
        let project = Project.test()
        let framework = FrameworkNode.test(path: AbsolutePath("/XcodeProj.framework"))
        let library = LibraryNode.test(path: AbsolutePath("/RxSwift.a"))
        let sdk = try SDKNode(name: "CoreData.framework", platform: .iOS, status: .required, source: .developer)

        let core = TargetNode.test(target: Target.test(name: "Core"), dependencies: [
            framework, library, sdk,
        ])
        let iOSApp = TargetNode.test(target: Target.test(name: "Tuist iOS"), dependencies: [core])
        let watchApp = TargetNode.test(target: Target.test(name: "Tuist watchOS"), dependencies: [core])

        let graph = Graph.test(entryNodes: [iOSApp, watchApp],
                               projects: [project],
                               precompiled: [framework, library],
                               targets: [project.path: [core, iOSApp, watchApp]])

        // When
        let got = subject.map(graph: graph, skipTestTargets: false, skipExternalDependencies: false)

        // Then
        var expected = DotGraph(directed: true)

        let nodes = makeNodes()
        expected.append(contentsOf: nodes.allNodes)
        expected.append(Edge(from: nodes.ios, to: nodes.core))
        expected.append(Edge(from: nodes.watch, to: nodes.core))
        expected.append(Edge(from: nodes.core, to: nodes.xcodeProj))
        expected.append(Edge(from: nodes.core, to: nodes.rxSwift))
        expected.append(Edge(from: nodes.core, to: nodes.coreData))

        XCTAssertEqual(got.dotRepresentation, expected.dotRepresentation)
    }

    func test_map_skipping_external_dependencies() throws {
        // Given
        let project = Project.test()
        let framework = FrameworkNode.test(path: AbsolutePath("/XcodeProj.framework"))
        let library = LibraryNode.test(path: AbsolutePath("/RxSwift.a"))
        let sdk = try SDKNode(name: "CoreData.framework", platform: .iOS, status: .required, source: .developer)

        let core = TargetNode.test(target: Target.test(name: "Core"), dependencies: [
            framework, library, sdk,
        ])
        let iOSApp = TargetNode.test(target: Target.test(name: "Tuist iOS"), dependencies: [core])
        let watchApp = TargetNode.test(target: Target.test(name: "Tuist watchOS"), dependencies: [core])

        let graph = Graph.test(entryNodes: [iOSApp, watchApp],
                               projects: [project],
                               precompiled: [framework, library],
                               targets: [project.path: [core, iOSApp, watchApp]])

        // When
        let got = subject.map(graph: graph, skipTestTargets: false, skipExternalDependencies: true)

        // Then

        var expected = DotGraph(directed: true)
        let nodes = makeNodes()
        expected.append(contentsOf: nodes.allNodes)

        expected.append(Edge(from: nodes.ios, to: nodes.core))
        expected.append(Edge(from: nodes.watch, to: nodes.core))

        XCTAssertEqual(got.dotRepresentation, expected.dotRepresentation)
    }

    // swiftlint:disable:next large_tuple
    private func makeNodes() -> (ios: Node, coreData: Node, rxSwift: Node, xcodeProj: Node, core: Node, watch: Node, allNodes: [Node]) {
        let iosAppNode = Node("Tuist iOS")
        let coreDataNode = Node("CoreData")
        let rxSwiftNode = Node("RxSwift")
        let xcodeProjNode = Node("XcodeProj")
        let coreNode = Node("Core")
        let watchOSNode = Node("Tuist watchOS")

        return (iosAppNode,
                coreDataNode,
                rxSwiftNode,
                xcodeProjNode,
                coreNode,
                watchOSNode,
                [iosAppNode,
                 coreDataNode,
                 rxSwiftNode,
                 xcodeProjNode,
                 coreNode, watchOSNode])
    }
}
