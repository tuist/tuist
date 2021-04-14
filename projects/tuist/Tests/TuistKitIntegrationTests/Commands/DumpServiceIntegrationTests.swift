import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoader
@testable import TuistSupportTesting

final class DumpServiceTests: TuistTestCase {
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

    func test_prints_the_manifest_when_swift_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let project = Project(
            name: "tuist",
            organizationName: "tuist",
            settings: nil,
            targets: [],
            resourceSynthesizers: []
        )
        """
        try config.write(
            toFile: tmpDir.appending(component: "Project.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString)
        let expected = "{\n  \"additionalFiles\": [\n\n  ],\n  \"name\": \"tuist\",\n  \"organizationName\": \"tuist\",\n  \"packages\": [\n\n  ],\n  \"resourceSynthesizers\": [\n\n  ],\n  \"schemes\": [\n\n  ],\n  \"targets\": [\n\n  ]\n}\n"

        XCTAssertPrinterOutputContains(expected)
    }
}
