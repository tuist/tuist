import Basic
import Foundation
import TuistCore
import Utility
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class CoreDataModelTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
    }
}
