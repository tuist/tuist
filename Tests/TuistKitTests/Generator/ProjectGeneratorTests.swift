import Basic
import Foundation
import TuistCore
import xcodeproj
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class ProjectGeneratorTests: XCTestCase {
    var subject: ProjectGenerator!
    var targetGenerator: TargetGenerator!
    var schemesGenerator: MockSchemesGenerator!
    var configGenerator: ConfigGenerator!
    var printer: MockPrinter!
    var system: MockSystem!
    var resourceLocator: MockResourceLocator!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        targetGenerator = TargetGenerator()
        schemesGenerator = MockSchemesGenerator()
        configGenerator = ConfigGenerator()
        printer = MockPrinter()
        system = MockSystem()
        resourceLocator = MockResourceLocator()
        fileHandler = try! MockFileHandler()
        subject = ProjectGenerator(targetGenerator: targetGenerator,
                                   configGenerator: configGenerator,
                                   schemesGenerator: schemesGenerator,
                                   printer: printer,
                                   system: system,
                                   resourceLocator: resourceLocator)
    }
}
