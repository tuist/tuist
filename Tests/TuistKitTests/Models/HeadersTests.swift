import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class HeadersTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
    }
}
