import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
import Utility
import XCTest

final class InstallerTests: XCTestCase {
    var printer: MockPrinter!
    var fileHandler: FileHandler!
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: Installer!
    var tmpDir: TemporaryDirectory!
    var system: MockSystem!
    
    override func setUp() {
        super.setUp()
        system = MockSystem()
        printer = MockPrinter()
        fileHandler = FileHandler()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = Installer(system: system,
                            printer: printer,
                            fileHandler: fileHandler,
                            buildCopier: buildCopier,
                            versionsController: versionsController)
    }

}
