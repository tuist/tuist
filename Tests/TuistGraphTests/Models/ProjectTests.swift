import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraphTesting
import XCTest
@testable import TuistGraph

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

    func test_defaultDebugBuildConfigurationName_when_defaultDebugConfigExists() {
        // Given
        let project = Project.test(settings: Settings.test())

        // When
        let got = project.defaultDebugBuildConfigurationName

        // Then
        XCTAssertEqual(got, "Debug")
    }

    func test_defaultDebugBuildConfigurationName_when_defaultDebugConfigDoesntExist() {
        // Given
        let settings = Settings.test(base: [:], configurations: [.debug("Test"): Configuration.test()])
        let project = Project.test(settings: settings)

        // When
        let got = project.defaultDebugBuildConfigurationName

        // Then
        XCTAssertEqual(got, "Test")
    }
}
