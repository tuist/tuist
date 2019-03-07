import Basic
import Foundation
import XCTest

@testable import TuistCore

final class AbsolutePathExtrasTests: XCTestCase {
    var fileHandler: FileHandling!

    override func setUp() {
        super.setUp()
        fileHandler = FileHandler()
    }
}
