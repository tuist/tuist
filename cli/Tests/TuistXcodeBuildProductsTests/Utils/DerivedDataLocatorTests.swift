import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistTesting
import TuistXcodeBuildProducts

@testable import TuistXcodeBuildProducts

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

    @Test(.withMockedEnvironment())
    func locate_replaces_spaces_in_hash_based_path_prefix() async throws {
        let projectPath = try AbsolutePath(
            validating: "/Users/developer/Projects/Example App/Example App.xcodeproj"
        )

        let result = try await subject.locate(for: projectPath)

        #expect(result.basename == "Example_App-haqlyztoonwvfngqefjfdacmpopg")
    }

    @Test(
        .withMockedEnvironment(),
        arguments: [
            ("/private/tmp/checkout/Tuist.xcworkspace", "Tuist-dpjpnkssqpthzhhhfxjnhiqlkqag"),
            ("/tmp/checkout/Tuist.xcworkspace", "Tuist-dpjpnkssqpthzhhhfxjnhiqlkqag"),
            ("/private/var/folders/ab/T/checkout/Tuist.xcworkspace", "Tuist-bxjqiptddbsgrbdcigrcfulltmsb"),
            ("/private/etc/checkout/Tuist.xcworkspace", "Tuist-fjxftmuartejcyclfypinywdfaup"),
            ("/private/opt/checkout/Tuist.xcworkspace", "Tuist-gusvznatpyrclbbpwtdlpbarvsiu"),
        ]
    )
    func locate_hashes_the_path_xcode_standardizes(path: String, expectedBasename: String) async throws {
        let projectPath = try AbsolutePath(validating: path)

        let result = try await subject.locate(for: projectPath)

        #expect(result.basename == expectedBasename)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_hashes_the_real_path_of_a_workspace_reached_through_a_symlink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let realDirectory = temporaryDirectory.appending(component: "real")
        let aliasDirectory = temporaryDirectory.appending(component: "alias")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: realDirectory.appending(component: "Tuist.xcworkspace").pathString),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: aliasDirectory.pathString,
            withDestinationPath: realDirectory.pathString
        )
        let aliasWorkspace = aliasDirectory.appending(component: "Tuist.xcworkspace")

        let aliasResult = try await subject.locate(for: aliasWorkspace)
        let realResult = try await subject.locate(for: realDirectory.appending(component: "Tuist.xcworkspace"))

        #expect(aliasResult == realResult)
        #expect(aliasResult.basename != "Tuist-\(try XcodeProjectPathHasher.hashString(for: aliasWorkspace.pathString))")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_hashes_the_path_xcode_standardizes_for_custom_absolute_location() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let customDerivedDataDirectory = temporaryDirectory.appending(component: "CustomDerivedData")
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.derivedDataLocationStub = .custom(customDerivedDataDirectory)

        let result = try await subject.locate(
            for: try AbsolutePath(validating: "/private/tmp/checkout/Tuist.xcworkspace")
        )

        #expect(result == customDerivedDataDirectory.appending(component: "Tuist-dpjpnkssqpthzhhhfxjnhiqlkqag"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_workspace_name_without_hash_for_relative_location() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Capivara.xcworkspace")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.derivedDataLocationStub = try .relativeToWorkspace(RelativePath(validating: ".derived-data"))

        let result = try await subject.locate(for: projectPath)

        #expect(result == temporaryDirectory.appending(components: ".derived-data", "Capivara"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_hash_based_path_for_custom_absolute_location() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Capivara.xcworkspace")
        let customDerivedDataDirectory = temporaryDirectory.appending(component: "CustomDerivedData")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.derivedDataLocationStub = .custom(customDerivedDataDirectory)

        let result = try await subject.locate(for: projectPath)

        #expect(result.parentDirectory == customDerivedDataDirectory)
        #expect(result.basename.hasPrefix("Capivara-"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_prefers_DERIVED_DATA_DIR_over_relative_location() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Capivara.xcworkspace")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.derivedDataLocationStub = try .relativeToWorkspace(RelativePath(validating: ".derived-data"))
        let buildDerivedDataPath = temporaryDirectory.appending(component: "build-derived-data")
        mockedEnvironment.variables["DERIVED_DATA_DIR"] = buildDerivedDataPath.pathString

        let result = try await subject.locate(for: projectPath)

        #expect(result == buildDerivedDataPath)
    }
}
