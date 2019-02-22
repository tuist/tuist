import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import XCTest

final class HeadersTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
    }
}
