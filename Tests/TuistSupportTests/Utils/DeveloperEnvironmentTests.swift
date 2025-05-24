import Foundation
import Path
import Testing
@testable import TuistSupport
@testable import TuistSupportTesting

@Suite struct DeveloperEnvironmentTests {
    private let subject: DeveloperEnvironment
    private let system: MockSystem
    private let fileHandler: MockFileHandler
    private let homeDirectoryPath = try! AbsolutePath(validating: "/tmp/OverridenHomeDirectory")

    init() {
        let mockedSystem = MockSystem()
        system = mockedSystem
        System._shared.mutate { $0 = mockedSystem }
        let path = homeDirectoryPath
        fileHandler = MockFileHandler { path }
        subject = DeveloperEnvironment(fileHandler: fileHandler)
    }

    @Test func test_derivedDataDirectory_calls_defaults_with_correct_parameters() throws {
        // Given
        system.succeedCommand(
            [
                "/usr/bin/defaults",
                "read",
                "com.apple.dt.Xcode",
                "IDEDerivedDataPathOverride",
            ],

            output: "/tmp/DerivedDataOverride"
        )

        // When
        let overriddeDir = subject.derivedDataDirectory

        // Then
        #expect(overriddeDir == "/tmp/DerivedDataOverride")
    }

    @Test func test_derivedDataDirectory_can_be_determined_from_custom_location() throws {
        // Given
        system.succeedCommand(
            [
                "/usr/bin/defaults",
                "read",
                "com.apple.dt.Xcode",
                "IDECustomDerivedDataLocation",
            ],

            output: "/tmp/DerivedDataOverride"
        )

        // When
        let overriddenDir = subject.derivedDataDirectory

        // Then
        #expect(overriddenDir == "/tmp/DerivedDataOverride")
    }

    @Test func test_derivedDataDirectory_returns_default_location_when_no_override() throws {
        // Given
        // No overrides

        // When
        let defaultDir = subject.derivedDataDirectory

        // Then
        #expect(defaultDir == homeDirectoryPath.appending(components: "Library", "Developer", "Xcode", "DerivedData"))
    }
}
