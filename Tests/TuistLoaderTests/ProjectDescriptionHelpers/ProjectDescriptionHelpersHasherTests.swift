import Basic
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

class ProjectDescriptionHelpersHasherTests: TuistUnitTestCase {
    var subject: ProjectDescriptionHelpersHasher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        subject = ProjectDescriptionHelpersHasher(tuistVersion: "3.2.1")
    }

    func test_hash() throws {
        // Given
        let temporaryDir = try temporaryPath()
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write("import ProjectDescription", path: helperPath, atomically: true)
        environment.tuistVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        for _ in 0 ..< 20 {
            let got = try subject.hash(helpersDirectory: temporaryDir)
            XCTAssertEqual(got, "d19835f96b16a558457fc33b169adb9c")
        }
    }

    func test_prefixHash() throws {
        // Given
        let path = AbsolutePath("/path/to/helpers")
        let pathString = path.pathString
        let index = pathString.index(pathString.startIndex, offsetBy: 7)
        let expected = String(pathString.md5[..<index])

        // When
        let got = subject.prefixHash(helpersDirectory: path)

        // Then
        XCTAssertEqual(got, expected)
    }
}
