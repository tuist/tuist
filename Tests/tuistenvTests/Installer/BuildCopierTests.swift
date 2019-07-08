import Basic
import Foundation
import TuistCore
import XCTest
@testable import tuistenv

final class BuildCopierTests: XCTestCase {
    var subject: BuildCopier!
    var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        fileManager = .default
        subject = BuildCopier()
    }

    func test_files() {
        XCTAssertEqual(BuildCopier.files, [
            "tuist",
            "ProjectDescription.swiftmodule",
            "ProjectDescription.swiftdoc",
            "libProjectDescription.dylib",
        ])
    }

    func test_copy() throws {
        let fromDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let fromPath = fromDir.path

        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path

        // Creating files
        try BuildCopier.files.forEach { file in
            let filePath = fromPath.appending(component: file)
            try Data().write(to: filePath.url)
        }
        let testFilePath = fromPath.appending(component: "test")
        try Data().write(to: testFilePath.url)

        try subject.copy(from: fromPath, to: toPath)

        XCTAssertEqual(toPath.glob("*").count, BuildCopier.files.count)
        XCTAssertFalse(fileManager.fileExists(atPath: toPath.appending(component: "test").pathString))
    }
}
