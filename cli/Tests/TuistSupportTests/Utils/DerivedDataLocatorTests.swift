import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistTesting

@testable import TuistSupport

struct DerivedDataLocatorTests {
    private let subject = DerivedDataLocator()

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_DERIVED_DATA_DIR_when_different_from_default() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        let customDerivedDataPath = temporaryDirectory.appending(component: "custom-derived-data")
        mockedEnvironment.variables["DERIVED_DATA_DIR"] = customDerivedDataPath.pathString

        let result = try await subject.locate(for: projectPath)

        #expect(result == customDerivedDataPath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_ignores_DERIVED_DATA_DIR_when_equal_to_default() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        let defaultDerivedDataDirectory = try await Environment.current.derivedDataDirectory()
        mockedEnvironment.variables["DERIVED_DATA_DIR"] = defaultDerivedDataDirectory.pathString

        let result = try await subject.locate(for: projectPath)

        #expect(result != defaultDerivedDataDirectory)
        #expect(result.parentDirectory == defaultDerivedDataDirectory)
        #expect(result.basename.hasPrefix("App-"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_BUILD_DIR_when_DERIVED_DATA_DIR_matches_default() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        let defaultDerivedDataDirectory = try await Environment.current.derivedDataDirectory()
        mockedEnvironment.variables["DERIVED_DATA_DIR"] = defaultDerivedDataDirectory.pathString

        let customDerivedDataPath = temporaryDirectory.appending(component: "custom-derived-data")
        mockedEnvironment.variables["BUILD_DIR"] =
            customDerivedDataPath.appending(components: "Build", "Products", "Debug-iphonesimulator").pathString

        let result = try await subject.locate(for: projectPath)

        #expect(result == customDerivedDataPath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_BUILD_DIR_when_DERIVED_DATA_DIR_not_set() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        let customDerivedDataPath = temporaryDirectory.appending(component: "custom-derived-data")
        mockedEnvironment.variables["BUILD_DIR"] =
            customDerivedDataPath.appending(components: "Build", "Products", "Debug").pathString

        let result = try await subject.locate(for: projectPath)

        #expect(result == customDerivedDataPath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_falls_back_to_hash_based_path() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let defaultDerivedDataDirectory = try await Environment.current.derivedDataDirectory()

        let result = try await subject.locate(for: projectPath)

        #expect(result.parentDirectory == defaultDerivedDataDirectory)
        #expect(result.basename.hasPrefix("App-"))
    }

    @Test
    func derivedDataRoot_extracts_root_from_BUILD_DIR() {
        let result = DerivedDataLocator.derivedDataRoot(
            from: "/Users/runner/custom-dd/Build/Products/Debug-iphonesimulator"
        )
        #expect(result?.pathString == "/Users/runner/custom-dd")
    }

    @Test
    func derivedDataRoot_extracts_root_from_BUILD_DIR_without_sdk() {
        let result = DerivedDataLocator.derivedDataRoot(
            from: "/Users/runner/custom-dd/Build/Products/Release"
        )
        #expect(result?.pathString == "/Users/runner/custom-dd")
    }

    @Test
    func derivedDataRoot_returns_nil_for_path_without_Build_Products() {
        let result = DerivedDataLocator.derivedDataRoot(from: "/Users/runner/some-path")
        #expect(result == nil)
    }
}
