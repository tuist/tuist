import Foundation
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
        let got = subject.map(graph: graph)

        // Then
        let expected = DotGraph(name: "Project Dependencies Graph",
                                type: .directed,
                                nodes: Set([
                                    .init(name: "Tuist iOS"),
                                    .init(name: "CoreData"),
                                    .init(name: "RxSwift"),
                                    .init(name: "XcodeProj"),
                                    .init(name: "Core"),
                                    .init(name: "Tuist watchOS"),
                                ]), dependencies: [
                                    .init(from: "Tuist iOS", to: "Core"),
                                    .init(from: "Tuist watchOS", to: "Core"),
                                    .init(from: "Core", to: "XcodeProj"),
                                    .init(from: "Core", to: "RxSwift"),
                                    .init(from: "Core", to: "CoreData"),
                                ])
        XCTAssertEqual(got, expected)
    }
}
