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
        subject = ProjectDescriptionHelpersBuilder()
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        super.tearDown()
    }

    func test_build_when_the_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        let helpersPath = path.appending(RelativePath("Tuist/ProjectDescriptionHelpers"))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let projectDescriptionPath = try resourceLocator.projectDescription()

        // When
        let got = try subject.build(at: path, projectDescriptionPath: projectDescriptionPath)

        // Then
        XCTAssertNotNil(got)
        XCTAssertTrue(FileHandler.shared.exists(got!.path))
        try got!.cleanup()
    }
}
