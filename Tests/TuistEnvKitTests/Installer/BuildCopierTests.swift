import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistEnvKit

final class BuildCopierTests: XCTestCase {
    var subject: BuildCopier!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
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
        // Given
        let fromPath = fileHandler.currentPath
        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path
        try BuildCopier.files.forEach { file in
            let filePath = fromPath.appending(component: file)
            try Data().write(to: filePath.url)
        }
        let testFilePath = fromPath.appending(component: "test")
        try Data().write(to: testFilePath.url)

        // When
        try subject.copy(from: fromPath, to: toPath)

        // Then
        XCTAssertEqual(toPath.glob("*").count, BuildCopier.files.count)
        XCTAssertFalse(fileHandler.exists(toPath.appending(component: "test")))
    }

    func test_copyFrameworks() throws {
        // Given
        let fromPath = fileHandler.currentPath
        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path
        try fileHandler.touch(fromPath.appending(component: "Sentry.framework"))

        // When
        try subject.copyFrameworks(from: fromPath, to: toPath)

        // Then
        XCTAssertTrue(fileHandler.exists(toPath.appending(component: "Sentry.framework")))
    }
}
