import Foundation
import Basic
@testable import TuistKit
import XCTest

final class ProjectTests: XCTestCase {
    func test_sortedTargetsForProjectScheme() {
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [
            framework, app, appTests, frameworkTests
            ])
        
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let frameworkNode = TargetNode(project: project,
                                       target: framework,
                                       dependencies: [])
        let frameworkTestsNode = TargetNode(project: project,
                                            target: frameworkTests,
                                            dependencies: [frameworkNode])
        let appNode = TargetNode(project: project,
                                 target: app,
                                 dependencies: [frameworkNode])
        let appTestsNode = TargetNode(project: project,
                                      target: appTests,
                                      dependencies: [appNode])
        
        cache.add(targetNode: frameworkNode)
        cache.add(targetNode: frameworkTestsNode)
        cache.add(targetNode: appNode)
        cache.add(targetNode: appTestsNode)

        let got = project.sortedTargetsForProjectScheme(graph: graph)
        XCTAssertEqual(got.count, 4)
        XCTAssertEqual(got[0], framework)
        XCTAssertEqual(got[1], app)
        XCTAssertEqual(got[2], appTests)
        XCTAssertEqual(got[3], frameworkTests)
    }
}
