import FileSystem
import Foundation
import Path
import TuistConstants
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
        try await fileSystem.makeDirectory(at: path.appending(component: Constants.tuistDirectoryName))
        try await fileSystem.makeDirectory(at: helpersPath)
        try await fileSystem.writeText(
            "import Foundation; class Test {}",
            at: helpersPath.appending(component: "Helper.swift")
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

    /// Reproduces the cross-process race in https://github.com/tuist/tuist/issues/9588.
    /// Multiple `ProjectDescriptionHelpersBuilder` instances stand in for separate
    /// `tuist` processes sharing the same `cacheDirectory`. The current
    /// implementation creates the module cache directory eagerly before
    /// `swiftc` finishes, so a sibling builder can observe the directory as
    /// "already compiled" (line 168 of ProjectDescriptionHelpersBuilder) and
    /// return a module whose dylib has not yet been written, surfacing as
    /// `JIT session error: Symbols not found` at load time.
    func test_build_is_atomic_across_concurrent_builders_sharing_cache() async throws {
        // Given
        let path = try temporaryPath()
        let helpersPath = path
            .appending(try RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try await fileSystem.makeDirectory(at: path.appending(component: Constants.tuistDirectoryName))
        try await fileSystem.makeDirectory(at: helpersPath)
        try await fileSystem.writeText(
            "import Foundation; class Test {}",
            at: helpersPath.appending(component: "Helper.swift")
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        // Repeat the race a handful of times with a fresh cache each cycle so
        // the test reliably hits the timing window where one builder observes
        // the cache directory created by another *before* swiftc has finished.
        let fs: FileSysteming = fileSystem
        let locator: HelpersDirectoryLocating = helpersDirectoryLocator
        for cycle in 0 ..< 16 {
            let cacheDirectory = path.appending(component: "shared-cache-\(cycle)")
            try await fs.makeDirectory(at: cacheDirectory)

            // When: each task uses its own builder, sharing only the on-disk cache,
            // mirroring multiple `tuist` processes racing on the same XDG_CACHE_HOME.
            let results = try await Array(0 ..< 8).concurrentMap { _ -> Bool in
                let builder = ProjectDescriptionHelpersBuilder(
                    cacheDirectory: cacheDirectory,
                    helpersDirectoryLocator: locator
                )
                let modules = try await builder.build(
                    at: path,
                    projectDescriptionSearchPaths: searchPaths,
                    projectDescriptionHelperPlugins: []
                )
                for module in modules {
                    let exists = try await fs.exists(module.path)
                    if !exists { return false }
                }
                return true
            }

            // Then: every returned module path must point at a dylib that already
            // exists on disk. Today this fails because builders short-circuit on
            // the directory existence check before swiftc has finished writing
            // the dylib to it.
            XCTAssertTrue(
                results.allSatisfy { $0 },
                "Cycle \(cycle): a builder returned a module whose dylib was not yet written"
            )
        }
    }

    func test_build_when_the_helpers_is_a_plugin() async throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path, helpersDirectoryLocator: helpersDirectoryLocator)

        let helpersPluginPath = path.appending(components: "Plugin", Constants.helpersDirectoryName)
        try await fileSystem.makeDirectory(at: path.appending(component: "Plugin"))
        try await fileSystem.makeDirectory(at: helpersPluginPath)
        try await fileSystem.writeText(
            "import Foundation; class Test {}",
            at: helpersPluginPath.appending(component: "Helper.swift")
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
