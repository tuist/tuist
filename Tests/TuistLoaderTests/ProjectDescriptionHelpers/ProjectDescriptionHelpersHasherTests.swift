import Basic
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

class ProjectDescriptionHelpersHasherTests: TuistUnitTestCase {
    var subject: ProjectDescriptionHelpersHasher!

    override func setUp() {
        super.setUp()
        subject = ProjectDescriptionHelpersHasher(tuistVersion: "3.2.1")
    }

    func test_hash() throws {
        // Given
        let temporaryDir = try temporaryPath()
        let versions = Versions.test()
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write("import ProjectDescription", path: helperPath, atomically: true)
        environment.tuistVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        for _ in 0 ..< 20 {
            let got = try subject.hash(helpersDirectory: temporaryDir, versions: versions)
            XCTAssertEqual(got, "80bd818a3c6eb57110056c17592caf0a")
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
