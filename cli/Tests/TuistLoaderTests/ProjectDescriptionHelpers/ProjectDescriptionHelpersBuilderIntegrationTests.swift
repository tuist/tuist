import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistConstants
import TuistCore
import TuistRootDirectoryLocator

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistTesting

struct ProjectDescriptionHelpersBuilderIntegrationTests {
    private let resourceLocator: ResourceLocator
    private let helpersDirectoryLocator: HelpersDirectoryLocating
    private let fileSystem: FileSysteming

    init() {
        resourceLocator = ResourceLocator()
        helpersDirectoryLocator = HelpersDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
        fileSystem = FileSystem()
    }

    @Test(.inTemporaryDirectory) func build_when_the_helpers_is_a_dylib() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let subject = ProjectDescriptionHelpersBuilder(
            cacheDirectory: path,
            helpersDirectoryLocator: helpersDirectoryLocator
        )
        let helpersPath = path.appending(try RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPath.appending(component: "Helper.swift"),
            atomically: true
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
        }

        #expect(Set(paths).count == 1)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/ProjectDescriptionHelpers.swiftmodule"]).collect().first
        #expect(swiftModule != nil)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libProjectDescriptionHelpers.dylib"]).collect().first
        #expect(dylib != nil)
        let helpersModule = try #require(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        #expect(exists)
    }

    @Test(.inTemporaryDirectory) func build_when_the_helpers_is_a_plugin() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path, helpersDirectoryLocator: helpersDirectoryLocator)

        let helpersPluginPath = path.appending(components: "Plugin", Constants.helpersDirectoryName)
        try FileHandler.shared.createFolder(path.appending(component: "Plugin"))
        try FileHandler.shared.createFolder(helpersPluginPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPluginPath.appending(component: "Helper.swift"),
            atomically: true
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        let plugins = [ProjectDescriptionHelpersPlugin(name: "Plugin", path: helpersPluginPath, location: .local)]

        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: plugins
            )
        }

        #expect(Set(paths).count == 1)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftmodule"]).collect().first
        #expect(swiftModule != nil)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libPlugin.dylib"]).collect().first
        #expect(dylib != nil)
        let helpersModule = try #require(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        #expect(exists)
    }
}
