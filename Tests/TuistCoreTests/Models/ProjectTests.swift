import Foundation
import TSCBasic
import XCTest
@testable import TuistCore

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

    func test_defaultDebugBuildConfigurationName_when_defaultDebugConfigExists() {
        // Given
        let settings = Settings.test(base: [:],
                                     debug: .test(),
                                     release: .test())
        let project = Project.test(settings: Settings.test())

        // When
        let got = project.defaultDebugBuildConfigurationName

        // Then
        XCTAssertEqual(got, settings.defaultDebugBuildConfiguration()?.name)
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
