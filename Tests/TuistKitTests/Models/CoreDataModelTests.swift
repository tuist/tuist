import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import XCTest

final class CoreDataModelTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
    }

    func test_init() throws {
        let dataModelPath = fileHandler.currentPath.appending(component: "3.xcdatamodel")
        try Data().write(to: dataModelPath.url)
        let json = JSON([
            "path": ".".toJSON(),
            "current_version": "3".toJSON(),
        ])

        let subject = try CoreDataModel(dictionary: json,
                                        projectPath: fileHandler.currentPath,
                                        fileHandler: fileHandler)

        XCTAssertEqual(subject.versions, [dataModelPath])
    }
}
