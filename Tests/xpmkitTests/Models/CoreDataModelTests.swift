import Basic
import Foundation
import Utility
import XCTest
import xpmcore
@testable import xpmcoreTesting
@testable import xpmkit

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

        let subject = try CoreDataModel(json: json,
                                        projectPath: fileHandler.currentPath,
                                        fileHandler: fileHandler)

        XCTAssertEqual(subject.versions, [dataModelPath])
    }
}
