import Basic
import Foundation
import TuistSupport
import TuistLoader
import XCTest

@testable import TuistTemplate
@testable import TuistSupportTesting

final class TemplateDescriptionHelpersBuilderIntegrationTests: TuistTestCase {
    var subject: TemplateDescriptionHelpersBuilder!
    var resourceLocator: ResourceLocator!
    var templateHelpersDirectoryLocator: TemplateHelpersDirectoryLocating!

    override func setUp() {
        super.setUp()
        resourceLocator = ResourceLocator()
        templateHelpersDirectoryLocator = TemplateHelpersDirectoryLocator()
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        templateHelpersDirectoryLocator = nil
        super.tearDown()
    }

    func test_build_when_the_helpers_is_a_dylib() throws {
        // Given
        let path = try temporaryPath()
        subject = TemplateDescriptionHelpersBuilder(cacheDirectory: path,
                                                    templateHelpersDirectoryLocator: templateHelpersDirectoryLocator)
        let helpersPath = path.appending(RelativePath("\(Constants.tuistDirectoryName)/\(Constants.templatesDirectoryName)/\(Constants.templateHelpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write("import Foundation; class Test {}", path: helpersPath.appending(component: "Helper.swift"), atomically: true)
        let templateDescriptionPath = try resourceLocator.templateDescription()
        print(helpersPath)

        // When
        let paths = try (0 ..< 3).map { _ in try subject.build(at: path, templateDescriptionPath: templateDescriptionPath) }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/TemplateDescriptionHelpers.swiftmodule").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/libTemplateDescriptionHelpers.dylib").first)
        XCTAssertNotNil(FileHandler.shared.glob(path, glob: "*/*/TemplateDescriptionHelpers.swiftdoc").first)
        XCTAssertTrue(FileHandler.shared.exists(paths.first!!))
    }
}
