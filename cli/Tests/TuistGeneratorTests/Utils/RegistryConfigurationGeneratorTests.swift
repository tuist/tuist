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
        let configurationPath = temporaryDirectory.appending(
            components: "Test.xcworkspace", "xcshareddata", "swiftpm", "configuration"
        )
        let fileSystem = FileSystem()

        let serverURL = try #require(URL(string: "https://tuist.dev"))

        try await subject.generate(
            at: configurationPath,
            serverURL: serverURL
        )

        let registriesJSONPath = configurationPath.appending(component: "registries.json")
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
        let configurationPath = temporaryDirectory.appending(
            components: "Test.xcworkspace", "xcshareddata", "swiftpm", "configuration"
        )
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: configurationPath)
        let registriesJSONPath = configurationPath.appending(component: "registries.json")
        try await fileSystem.writeText("old content", at: registriesJSONPath)

        let serverURL = try #require(URL(string: "https://cloud.tuist.io"))

        try await subject.generate(
            at: configurationPath,
            serverURL: serverURL
        )

        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        #expect(content.contains("\"url\": \"https://cloud.tuist.io/api/registry/swift\""))
        #expect(!content.contains("old content"))
    }

    @Test(.inTemporaryDirectory)
    func generate_handlesURLWithTrailingSlash() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configurationPath = temporaryDirectory.appending(
            components: "Test.xcworkspace", "xcshareddata", "swiftpm", "configuration"
        )
        let fileSystem = FileSystem()

        let serverURL = try #require(URL(string: "https://tuist.dev/"))

        try await subject.generate(
            at: configurationPath,
            serverURL: serverURL
        )

        let registriesJSONPath = configurationPath.appending(component: "registries.json")
        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        #expect(content.contains("\"url\": \"https://tuist.dev/api/registry/swift\""))
    }

    @Test
    func registryConfigurationJSON_generatesCorrectJSON() throws {
        let serverURL = try #require(URL(string: "https://tuist.dev"))

        let json = RegistryConfigurationGenerator.registryConfigurationJSON(serverURL: serverURL)

        #expect(json.contains("\"url\": \"https://tuist.dev/api/registry/swift\""))
        #expect(json.contains("\"tuist.dev\""))
        #expect(json.contains("\"loginAPIPath\": \"/api/registry/swift/login\""))
        #expect(json.contains("\"version\": 1"))
        #expect(json.contains("\"onUnsigned\": \"silentAllow\""))
    }
}
