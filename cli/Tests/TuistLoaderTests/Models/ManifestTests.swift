import FileSystem
import FileSystemTesting
import Foundation
import Testing

@testable import TuistLoader
@testable import TuistTesting

struct ManifestTests {
    @Test(.inTemporaryDirectory) func test_fileName() throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory).appending(component: "folder")

        #expect(Manifest.project.fileName(temporaryPath) == "Project.swift")
        #expect(Manifest.workspace.fileName(temporaryPath) == "Workspace.swift")
        #expect(Manifest.config.fileName(temporaryPath) == "Config.swift")
        #expect(Manifest.package.fileName(temporaryPath) == "Package.swift")
        #expect(Manifest.packageSettings.fileName(temporaryPath) == "Package.swift")
        #expect(Manifest.plugin.fileName(temporaryPath) == "Plugin.swift")
        #expect(Manifest.template.fileName(temporaryPath) == "folder.swift")
    }
}
