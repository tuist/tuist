import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ProjectDescriptionHelpersBuilderIntegrationTests: TuistTestCase {
    var subject: ProjectDescriptionHelpersBuilder!
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

    func test_build_when_the_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path,
                                                   helpersDirectoryLocator: helpersDirectoryLocator)
        let helpersPath = path.appending(RelativePath("\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        // When
        let paths = try (0 ..< 3).map { _ in try subject.build(at: path, projectDescriptionSearchPaths: searchPaths) }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libProjectDescriptionHelpers.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftdoc").first)
        XCTAssertTrue(FileHandler.shared.exists(paths.first!!))
    }
}
