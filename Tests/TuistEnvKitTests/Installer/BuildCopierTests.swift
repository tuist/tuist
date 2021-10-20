import Foundation
import TSCBasic
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistEnvKit

final class BuildCopierTests: XCTestCase {
    var subject: BuildCopier!
    var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        fileManager = .default
        subject = BuildCopier()
    }

    override func tearDown() {
        fileManager = nil
        subject = nil
        super.tearDown()
    }

    func test_files() {
        XCTAssertEqual(BuildCopier.files, [
            "tuist",
            Constants.templatesDirectoryName,
            Constants.vendorDirectoryName,
            "ProjectDescription.swiftmodule",
            "ProjectDescription.swiftdoc",
            "ProjectDescription.swiftinterface",
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

    func test_copy_without_templates() throws {
        let fromDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let fromPath = fromDir.path

        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path

        // Creating files
        try BuildCopier.files
            // Simulate Templates directory not being present
            .filter { $0 != Constants.templatesDirectoryName }
            .forEach { file in
                let filePath = fromPath.appending(component: file)
                try Data().write(to: filePath.url)
            }
        let testFilePath = fromPath.appending(component: "test")
        try Data().write(to: testFilePath.url)

        try subject.copy(from: fromPath, to: toPath)

        XCTAssertEqual(toPath.glob("*").count, BuildCopier.files.count - 1)
        XCTAssertFalse(fileManager.fileExists(atPath: toPath.appending(component: "test").pathString))
    }
}
