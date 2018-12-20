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

    func test_init() throws {
        let publicPath = fileHandler.currentPath.appending(component: "public")
        let publicHeaderPath = publicPath.appending(component: "public.h")

        let privatePath = fileHandler.currentPath.appending(component: "private")
        let privateHeaderPath = privatePath.appending(component: "private.h")

        let projectPath = fileHandler.currentPath.appending(component: "project")
        let projectHeaderPath = projectPath.appending(component: "project.h")

        try fileHandler.createFolder(publicPath)
        try fileHandler.createFolder(privatePath)
        try fileHandler.createFolder(projectPath)

        try Data().write(to: publicHeaderPath.url)
        try Data().write(to: privateHeaderPath.url)
        try Data().write(to: projectHeaderPath.url)

        let json = JSON.dictionary([
            "public": "public/*".toJSON(),
            "private": "private/*".toJSON(),
            "project": "project/*".toJSON(),
        ])

        let subject = try Headers(dictionary: json,
                                  projectPath: fileHandler.currentPath,
                                  fileHandler: fileHandler)

        XCTAssertEqual(subject.public, [publicHeaderPath])
        XCTAssertEqual(subject.private, [privateHeaderPath])
        XCTAssertEqual(subject.project, [projectHeaderPath])
    }
}
