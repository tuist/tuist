import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraphTesting
import XCTest
@testable import TuistGraph

final class ProjectTests: XCTestCase {
    func test_codable() {
        // Given
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let subject = Project.test(targets: [
            framework, app, appTests, frameworkTests,
        ])

        // Then
        XCTAssertCodable(subject)
    }

    func test_sortedTargetsForProjectScheme() {
        // Given
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [
            framework, app, appTests, frameworkTests,
        ])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    framework.name: framework,
                    frameworkTests.name: frameworkTests,
                    app.name: app,
                    appTests.name: appTests,
                ],
            ],
            dependencies: [
                .target(name: frameworkTests.name, path: project.path): [
                    .target(name: framework.name, path: project.path),
                ],
                .target(name: appTests.name, path: project.path): [
                    .target(name: app.name, path: project.path),
                ],
            ]
        )

        // When
        let got = project.sortedTargetsForProjectScheme(graph: graph)

        // Then
        XCTAssertEqual(got.count, 4)
        XCTAssertEqual(got[0], app)
        XCTAssertEqual(got[1], framework)
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
