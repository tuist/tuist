
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
        let dictionary = JSON.dictionary(["globs": ["sources/*"].toJSON()])
        let got = try FileList(json: dictionary)
            
        XCTAssertEqual(got.globs, ["sources/*"])
    }
}
