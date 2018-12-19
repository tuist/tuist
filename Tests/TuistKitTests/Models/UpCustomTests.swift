import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpCustomTests: XCTestCase {
    var system: MockSystem!
    var printer: MockPrinter!
    var fileHandler: MockFileHandler!
    var subject: UpCustom!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        printer = MockPrinter()
        fileHandler = try! MockFileHandler()
        subject = UpCustom(name: "test",
                           meet: ["./install.sh"],
                           isMet: ["which", "tool"])
    }
}
