import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistGenerator

struct RegistryConfigurationGeneratorTests {
    private let subject = RegistryConfigurationGenerator()

    @Test(.inTemporaryDirectory)
    func generate_createsRegistryConfiguration() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = temporaryDirectory.appending(component: "Test.xcworkspace")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: workspacePath)

        let serverURL = try #require(URL(string: "https://tuist.dev"))

        try await subject.generate(
            workspacePath: workspacePath,
            serverURL: serverURL
        )

        let registriesJSONPath = workspacePath.appending(
            components: "xcshareddata", "swiftpm", "configuration", "registries.json"
        )
        let exists = try await fileSystem.exists(registriesJSONPath)
        #expect(exists)

        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        #expect(content.contains("\"url\": \"https://tuist.dev/api/registry/swift\""))
        #expect(content.contains("\"tuist.dev\""))
        #expect(content.contains("\"loginAPIPath\": \"/api/registry/swift/login\""))
        #expect(content.contains("\"version\": 1"))
    }

    @Test(.inTemporaryDirectory)
    func generate_replacesExistingConfiguration() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = temporaryDirectory.appending(component: "Test.xcworkspace")
        let fileSystem = FileSystem()
        let configurationPath = workspacePath.appending(
            components: "xcshareddata", "swiftpm", "configuration"
        )
        try await fileSystem.makeDirectory(at: configurationPath)
        let registriesJSONPath = configurationPath.appending(component: "registries.json")
        try await fileSystem.writeText("old content", at: registriesJSONPath)

        let serverURL = try #require(URL(string: "https://cloud.tuist.io"))

        try await subject.generate(
            workspacePath: workspacePath,
            serverURL: serverURL
        )

        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        #expect(content.contains("\"url\": \"https://cloud.tuist.io/api/registry/swift\""))
        #expect(!content.contains("old content"))
    }

    @Test(.inTemporaryDirectory)
    func generate_handlesURLWithTrailingSlash() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = temporaryDirectory.appending(component: "Test.xcworkspace")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: workspacePath)

        let serverURL = try #require(URL(string: "https://tuist.dev/"))

        try await subject.generate(
            workspacePath: workspacePath,
            serverURL: serverURL
        )

        let registriesJSONPath = workspacePath.appending(
            components: "xcshareddata", "swiftpm", "configuration", "registries.json"
        )
        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        #expect(content.contains("\"url\": \"https://tuist.dev/api/registry/swift\""))
    }
}
