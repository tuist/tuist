import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistTesting
@testable import TuistXcodeBuildProducts

struct DerivedDataLocatorTests {
    private let subject = DerivedDataLocator()

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: ["xcworkspace", "xcodeproj"])
    func locate_uses_per_user_workspace_custom_root(extensionName: String) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "App.\(extensionName)")
        let workspacePath = extensionName == "xcodeproj" ? projectPath.appending(component: "project.xcworkspace") : projectPath
        let root = path.appending(component: "Custom DerivedData")
        let settingsPath = workspacePath.appending(
            components: "xcuserdata",
            "\(NSUserName()).xcuserdatad",
            "WorkspaceSettings.xcsettings"
        )
        try await FileSystem().makeDirectory(at: settingsPath.parentDirectory)
        try await FileSystem().writeAsPlist([
            "DerivedDataLocationStyle": "AbsolutePath",
            "DerivedDataCustomLocation": root.pathString,
        ], at: settingsPath)

        let result = try await subject.locate(for: projectPath)

        let hash = try XcodeProjectPathHasher.hashString(for: projectPath.pathString)
        #expect(result == root.appending(component: "App-\(hash)"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_uses_per_user_workspace_relative_root_without_hash() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "App.xcworkspace")
        let settingsPath = projectPath.appending(
            components: "xcuserdata",
            "\(NSUserName()).xcuserdatad",
            "WorkspaceSettings.xcsettings"
        )
        try await FileSystem().makeDirectory(at: settingsPath.parentDirectory)
        try await FileSystem().writeAsPlist([
            "DerivedDataLocationStyle": "WorkspaceRelativePath",
            "DerivedDataCustomLocation": "Relative Data",
        ], at: settingsPath)

        #expect(try await subject.locate(for: projectPath) == path.appending(components: "Relative Data", "App"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: ["DERIVED_DATA_DIR", "BUILD_DIR", "BUILD_DIR_same_root"])
    func locate_build_environment_overrides_workspace_settings(variable: String) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "App.xcworkspace")
        let settingsPath = projectPath.appending(
            components: "xcuserdata",
            "\(NSUserName()).xcuserdatad",
            "WorkspaceSettings.xcsettings"
        )
        try await FileSystem().makeDirectory(at: settingsPath.parentDirectory)
        try await FileSystem().writeAsPlist([
            "DerivedDataLocationStyle": "AbsolutePath",
            "DerivedDataCustomLocation": path.appending(component: "Workspace Data").pathString,
        ], at: settingsPath)
        let override = path.appending(component: variable == "BUILD_DIR_same_root" ? "Workspace Data" : "Actual Build")
        let environment = try #require(Environment.mocked)
        let environmentKey = variable.hasPrefix("BUILD_DIR") ? "BUILD_DIR" : "DERIVED_DATA_DIR"
        environment.variables[environmentKey] = environmentKey == "BUILD_DIR"
            ? override.appending(components: "Build", "Products", "Debug").pathString : override.pathString

        #expect(try await subject.locate(for: projectPath) == override)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: ["Default", "missing"])
    func locate_workspace_default_uses_global_preferences(style: String) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "App.xcworkspace")
        let settingsPath = projectPath.appending(
            components: "xcuserdata",
            "\(NSUserName()).xcuserdatad",
            "WorkspaceSettings.xcsettings"
        )
        try await FileSystem().makeDirectory(at: settingsPath.parentDirectory)
        var settings = ["DerivedDataCustomLocation": path.appending(component: "Stale Path").pathString]
        if style != "missing" { settings["DerivedDataLocationStyle"] = style }
        try await FileSystem().writeAsPlist(settings, at: settingsPath)
        let environment = try #require(Environment.mocked)
        let globalRoot = path.appending(component: "Global Data")
        environment.derivedDataLocationStub = .custom(globalRoot)

        let result = try await subject.locate(for: projectPath)

        #expect(result.parentDirectory == globalRoot)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_shared_settings_do_not_override_global_preferences() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "App.xcworkspace")
        let settingsPath = projectPath.appending(components: "xcshareddata", "WorkspaceSettings.xcsettings")
        try await FileSystem().makeDirectory(at: settingsPath.parentDirectory)
        try await FileSystem().writeAsPlist([
            "DerivedDataLocationStyle": "AbsolutePath",
            "DerivedDataCustomLocation": path.appending(component: "Shared Data").pathString,
        ], at: settingsPath)

        let result = try await subject.locate(for: projectPath)

        #expect(result.parentDirectory == (try await Environment.current.derivedDataDirectory()))
    }

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
