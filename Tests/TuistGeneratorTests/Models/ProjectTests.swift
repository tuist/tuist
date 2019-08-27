import Basic
import Foundation
import XCTest
@testable import TuistGenerator

final class ProjectTests: XCTestCase {
    func test_sortedTargetsForProjectScheme() {
        // Given
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

        // When
        let got = project.sortedTargetsForProjectScheme(graph: graph)

        // Then
        XCTAssertEqual(got.count, 4)
        XCTAssertEqual(got[0], framework)
        XCTAssertEqual(got[1], app)
        XCTAssertEqual(got[2], appTests)
        XCTAssertEqual(got[3], frameworkTests)
    }

    func test_projectDefaultFileName() {
        // Given
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)

        // When
        let project = Project.test(name: "SomeProjectName", targets: [
            framework, app, appTests, frameworkTests,
        ])

        // Then
        XCTAssertEqual(project.fileName, "SomeProjectName")
        XCTAssertEqual(project.name, "SomeProjectName")
    }
}
