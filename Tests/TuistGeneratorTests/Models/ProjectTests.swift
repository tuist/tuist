import Basic
import Foundation
import XCTest
@testable import TuistGenerator

final class ProjectTests: XCTestCase {
    func test_sortedTargetsForProjectScheme() {
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [
            framework, app, appTests, frameworkTests,
        ])

        let graph = Graph.create(project: project, dependencies: [
            (target: framework, dependencies: []),
            (target: frameworkTests, dependencies: [framework]),
            (target: app, dependencies: [framework]),
            (target: appTests, dependencies: [app]),
        ])

        let got = project.sortedTargetsForProjectScheme(graph: graph)
        XCTAssertEqual(got.count, 4)
        XCTAssertEqual(got[0], framework)
        XCTAssertEqual(got[1], app)
        XCTAssertEqual(got[2], appTests)
        XCTAssertEqual(got[3], frameworkTests)
    }
}
