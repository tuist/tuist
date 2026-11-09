import FileSystem
import FileSystemTesting
import Foundation
import Path
import SwiftyJSON
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
        let json = try JSON(data: Data(content.utf8))

        #expect(json["registries"]["[default]"]["url"].string == "https://tuist.dev/api/registry/swift")
        #expect(json["authentication"]["tuist.dev"]["loginAPIPath"].string == "/api/registry/swift/login")
        #expect(json["version"].int == 1)
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

        let serverURL = try #require(URL(string: "https://tuist.dev"))

        try await subject.generate(
            at: configurationPath,
            serverURL: serverURL
        )

        let content = try await fileSystem.readTextFile(at: registriesJSONPath)
        let json = try JSON(data: Data(content.utf8))

        #expect(json["registries"]["[default]"]["url"].string == "https://tuist.dev/api/registry/swift")
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
        let json = try JSON(data: Data(content.utf8))

        #expect(json["registries"]["[default]"]["url"].string == "https://tuist.dev/api/registry/swift")
    }

    @Test
    func registryConfigurationJSON_generatesCorrectJSON() throws {
        let serverURL = try #require(URL(string: "https://tuist.dev"))

        let jsonString = RegistryConfigurationGenerator.registryConfigurationJSON(serverURL: serverURL)
        let json = try JSON(data: Data(jsonString.utf8))

        #expect(json["registries"]["[default]"]["url"].string == "https://tuist.dev/api/registry/swift")
        #expect(json["authentication"]["tuist.dev"]["loginAPIPath"].string == "/api/registry/swift/login")
        #expect(json["version"].int == 1)
        #expect(json["security"]["default"]["signing"]["onUnsigned"].string == "silentAllow")
    }
}
