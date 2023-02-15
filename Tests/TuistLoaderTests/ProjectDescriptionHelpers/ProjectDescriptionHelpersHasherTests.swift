import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

class ProjectDescriptionHelpersHasherTests: TuistUnitTestCase {
    var subject: ProjectDescriptionHelpersHasher!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = ProjectDescriptionHelpersHasher(tuistVersion: "3.2.1")
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_hash() throws {
        // Given
        let temporaryDir = try temporaryPath()
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write("import ProjectDescription", path: helperPath, atomically: true)
        environment.manifestLoadingVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        for _ in 0 ..< 20 {
            let got = try subject.hash(helpersDirectory: temporaryDir)
            XCTAssertEqual(got, "c9910732734d9dcf509bdb7538aed526")
        }
    }

    func test_prefixHash() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/to/helpers")
        let pathString = path.pathString
        let index = pathString.index(pathString.startIndex, offsetBy: 7)
        let expected = String(pathString.md5[..<index])

        // When
        let got = subject.prefixHash(helpersDirectory: path)

        // Then
        XCTAssertEqual(got, expected)
    }
}
