import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class HelpersBuilderIntegrationTests: TuistTestCase {
    var subject: HelpersBuilder!
    var resourceLocator: ResourceLocator!
    var helpersDirectoryLocator: HelpersDirectoryLocating!

    override func setUp() {
        super.setUp()
        resourceLocator = ResourceLocator()
        helpersDirectoryLocator = HelpersDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        helpersDirectoryLocator = nil
        super.tearDown()
    }

    func test_build_when_the_project_description_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        subject = HelpersBuilder(
            cacheDirectory: path,
            helpersDirectoryLocator: helpersDirectoryLocator
        )
        let helpersPath = path.appending(RelativePath("\(Constants.tuistDirectoryName)/\(Constants.projectDescriptionHelpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ModuleSearchPaths.paths(for: projectDescriptionPath)

        // When
        let paths = try (0 ..< 3).map { _ in
            try subject.buildProjectDescriptionHelpers(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libProjectDescriptionHelpers.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftdoc").first)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        XCTAssertTrue(FileHandler.shared.exists(helpersModule.path))
    }
    
    func test_build_when_the_project_automation_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        subject = HelpersBuilder(
            cacheDirectory: path,
            helpersDirectoryLocator: helpersDirectoryLocator
        )
        let helpersPath = path.appending(RelativePath("\(Constants.tuistDirectoryName)/\(Constants.projectAutomationHelpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let projectAutomationPath = try resourceLocator.projectAutomation()
        let searchPaths = ModuleSearchPaths.paths(for: projectAutomationPath)

        // When
        let paths = try (0 ..< 3).map { _ in
            try subject.buildProjectAutomationHelpers(
                at: path,
                projectAutomationSearchPaths: searchPaths
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectAutomationHelpers.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libProjectAutomationHelpers.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectAutomationHelpers.swiftdoc").first)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        XCTAssertTrue(FileHandler.shared.exists(helpersModule.path))
    }

    func test_build_when_the_helpers_is_a_plugin() throws {
        // Given
        let path = try temporaryPath()
        subject = HelpersBuilder(cacheDirectory: path, helpersDirectoryLocator: helpersDirectoryLocator)

        let helpersPluginPath = path.appending(components: "Plugin", Constants.projectDescriptionHelpersDirectoryName)
        try FileHandler.shared.createFolder(path.appending(component: "Plugin"))
        try FileHandler.shared.createFolder(helpersPluginPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPluginPath.appending(component: "Helper.swift"), atomically: true)
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ModuleSearchPaths.paths(for: projectDescriptionPath)
        let plugins = [ProjectDescriptionHelpersPlugin(name: "Plugin", path: helpersPluginPath, location: .local)]

        // When
        let paths = try (0 ..< 3).map { _ in
            try subject.buildProjectDescriptionHelpers(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: plugins
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/Plugin.swiftsourceinfo").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/Plugin.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libPlugin.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/Plugin.swiftdoc").first)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        XCTAssertTrue(FileHandler.shared.exists(helpersModule.path))
    }
}
