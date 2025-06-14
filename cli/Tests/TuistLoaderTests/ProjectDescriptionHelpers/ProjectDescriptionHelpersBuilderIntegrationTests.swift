import FileSystem
import Foundation
import Path
import TuistCore
import TuistRootDirectoryLocator
import XCTest

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistTesting

final class ProjectDescriptionHelpersBuilderIntegrationTests: TuistTestCase {
    private var subject: ProjectDescriptionHelpersBuilder!
    private var resourceLocator: ResourceLocator!
    private var helpersDirectoryLocator: HelpersDirectoryLocating!
    private var fileSystem: FileSysteming!

    override func setUp() {
        super.setUp()
        resourceLocator = ResourceLocator()
        helpersDirectoryLocator = HelpersDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
        fileSystem = FileSystem()
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        helpersDirectoryLocator = nil
        fileSystem = nil
        super.tearDown()
    }

    func test_build_when_the_helpers_is_a_dylib() async throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(
            cacheDirectory: path,
            helpersDirectoryLocator: helpersDirectoryLocator
        )
        let helpersPath = path
            .appending(try RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPath.appending(component: "Helper.swift"),
            atomically: true
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        // When
        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await self.subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/ProjectDescriptionHelpers.swiftmodule"])
            .collect().first
        XCTAssertNotNil(swiftModule)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libProjectDescriptionHelpers.dylib"]).collect().first
        XCTAssertNotNil(dylib)
        let swiftdoc = try await fileSystem.glob(directory: path, include: ["*/ProjectDescriptionHelpers.swiftdoc"]).collect()
            .first
        XCTAssertNotNil(swiftdoc)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        XCTAssertTrue(exists)
    }

    func test_build_when_the_helpers_is_a_plugin() async throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path, helpersDirectoryLocator: helpersDirectoryLocator)

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

        // When
        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await self.subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: plugins
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        let swiftSourceInfo = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftsourceinfo"]).collect().first
        XCTAssertNotNil(swiftSourceInfo)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftmodule"]).collect().first
        XCTAssertNotNil(swiftModule)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libPlugin.dylib"]).collect().first
        XCTAssertNotNil(dylib)
        let swiftDoc = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftdoc"]).collect().first
        XCTAssertNotNil(swiftDoc)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        XCTAssertTrue(exists)
    }
}
