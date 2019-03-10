
import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class FileListTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        fileHandler = try! MockFileHandler()
        super.setUp()
    }

    func test_init() throws {
        let sources: [String] = ["sources/*"]

        let dictionary = JSON.dictionary(["globs": .array(sources.map { $0.toJSON() })])
        let got = try FileList(json: dictionary)

        XCTAssertEqual(got.globs, ["sources/*"])
    }
}
