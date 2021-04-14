import Foundation
import TSCBasic
import TuistLoader
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class DumpServiceTests: TuistUnitTestCase {
    var errorHandler: MockErrorHandler!
    var subject: DumpService!
    var manifestLoading: ManifestLoading!

    override func setUp() {
        super.setUp()
        errorHandler = MockErrorHandler()
        manifestLoading = ManifestLoader()
        subject = DumpService(manifestLoader: manifestLoading)
    }

    override func tearDown() {
        errorHandler = nil
        manifestLoading = nil
        subject = nil
        super.tearDown()
    }

    func test_run_throws_when_file_doesnt_exist() throws {
        let tmpDir = try temporaryPath()
        XCTAssertThrowsSpecific(
            try subject.run(path: tmpDir.pathString),
            ManifestLoaderError.manifestNotFound(.project, tmpDir)
        )
    }

    func test_run_throws_when_the_manifest_loading_fails() throws {
        let tmpDir = try temporaryPath()
        try "invalid config".write(
            toFile: tmpDir.appending(component: "Project.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertThrowsError(try subject.run(path: tmpDir.pathString))
    }
}
