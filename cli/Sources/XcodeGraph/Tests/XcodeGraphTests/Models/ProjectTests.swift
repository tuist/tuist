import Foundation
import Path
import XCTest
@testable import XcodeGraph

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
