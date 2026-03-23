import Foundation
import Path
import Testing
@testable import XcodeGraph

struct ProjectTests {
    @Test func test_codable() throws {
        // Given
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let subject = Project.test(targets: [
            framework, app, appTests, frameworkTests,
        ])

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Project.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_defaultDebugBuildConfigurationName_when_defaultDebugConfigExists() {
        // Given
        let project = Project.test(settings: Settings.test())

        // When
        let got = project.defaultDebugBuildConfigurationName

        // Then
        #expect(got == "Debug")
    }

    @Test func test_defaultDebugBuildConfigurationName_when_defaultDebugConfigDoesntExist() {
        // Given
        let settings = Settings.test(base: [:], configurations: [.debug("Test"): Configuration.test()])
        let project = Project.test(settings: settings)

        // When
        let got = project.defaultDebugBuildConfigurationName

        // Then
        #expect(got == "Test")
    }
}
