import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectDescriptionHelpersBuilderIntegrationTests: TuistTestCase {
    var subject: ProjectDescriptionHelpersBuilder!
    var resourceLocator: ResourceLocator!

    override func setUp() {
        super.setUp()
        resourceLocator = ResourceLocator()
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        super.tearDown()
    }

    func test_build_when_the_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path)
        let helpersPath = path.appending(RelativePath("Tuist/ProjectDescriptionHelpers"))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let projectDescriptionPath = try resourceLocator.projectDescription()

        // When
        _ = try subject.build(at: path, projectDescriptionPath: projectDescriptionPath)
        let got = try subject.build(at: path, projectDescriptionPath: projectDescriptionPath)

        // Then
        XCTAssertNotNil(got)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libProjectDescriptionHelpers.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/ProjectDescriptionHelpers.swiftdoc").first)
        XCTAssertTrue(FileHandler.shared.exists(got!))
    }
}
