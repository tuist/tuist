import Foundation
import Path
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

//  Inspired by: https://gist.github.com/efirestone/ce01ae109e08772647eb061b3bb387c3

final class GlobTests: TuistTestCase {
    let temporaryFiles = ["foo", "bar", "baz", "dir1/file1.ext", "dir1/dir2/dir3/file2.ext", "dir1/**(_:_:)/file3.ext"]
    private var temporaryDirectory: AbsolutePath!

    override func setUpWithError() throws {
        super.setUp()

        temporaryDirectory = try temporaryPath()
    }

    func testNothingMatches() async throws {
        try await createFiles(temporaryFiles, content: "")
        let pattern = "nothing"
        XCTAssertEmpty(temporaryDirectory.glob(pattern))
    }

    func testBraces() async throws {
        try await createFiles(temporaryFiles, content: "")
        let pattern = "ba{r,y,z}"
        XCTAssertEqual(
            temporaryDirectory.glob(pattern),
            [temporaryDirectory.appending(component: "bar"), temporaryDirectory.appending(component: "baz")]
        )
    }

    // MARK: - Globstar - Bash v4

    func testGlobstarNoSlash() async throws {
        try await createFiles(temporaryFiles, content: "")
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**"
        let expected: [String] = [
            ".",
            "bar",
            "baz",
            "dir1",
            "dir1/**(_:_:)",
            "dir1/**(_:_:)/file3.ext",
            "dir1/dir2",
            "dir1/dir2/dir3",
            "dir1/dir2/dir3/file2.ext",
            "dir1/file1.ext",
            "foo",
        ]

        let result = temporaryDirectory.glob("**").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }

    func testGlobstarWithSlash() async throws {
        try await createFiles(temporaryFiles, content: "")
        // `**/` is treated as same as `**` with Tuist since it converts pattern string to RelativePath.
        // This is not an expected behavior for bash glob but this should be kept to avoid unexpected source file drops.
        let expected: [String] = [
            ".",
            "bar",
            "baz",
            "dir1",
            "dir1/**(_:_:)",
            "dir1/**(_:_:)/file3.ext",
            "dir1/dir2",
            "dir1/dir2/dir3",
            "dir1/dir2/dir3/file2.ext",
            "dir1/file1.ext",
            "foo",
        ]

        let result = temporaryDirectory.glob("**/").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }

    func testGlobstarWithSlashAndWildcard() async throws {
        try await createFiles(temporaryFiles, content: "")
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**/*"
        let expected: [String] = [
            "bar",
            "baz",
            "dir1",
            "dir1/**(_:_:)",
            "dir1/**(_:_:)/file3.ext",
            "dir1/dir2",
            "dir1/dir2/dir3",
            "dir1/dir2/dir3/file2.ext",
            "dir1/file1.ext",
            "foo",
        ]

        let result = temporaryDirectory.glob("**/*").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }

    func testPatternEndsWithGlobstar() async throws {
        try await createFiles(temporaryFiles, content: "")
        let expected: [String] = [
            "dir1",
            "dir1/**(_:_:)",
            "dir1/**(_:_:)/file3.ext",
            "dir1/dir2",
            "dir1/dir2/dir3",
            "dir1/dir2/dir3/file2.ext",
            "dir1/file1.ext",
        ]

        let result = temporaryDirectory.glob("dir1/**").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }

    func testDoubleGlobstar() async throws {
        try await createFiles(temporaryFiles, content: "")
        let expected: [String] = [
            "dir1/dir2/dir3",
            "dir1/dir2/dir3/file2.ext",
        ]

        let result = temporaryDirectory.glob("**/dir2/**/*").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }
    
    func testGlobstarWithOtherGlobPatterns() async throws {
        let files = [
            "dir1/vDirectory/dir3/foo.swift",
            "dir1/aDirectory/dir3/foo.swift"
        ]
        try await createFiles(files, content: "")
        let expected: [String] = [
            "dir1/vDirectory/dir3/foo.swift"
        ]
        
        let result = temporaryDirectory.glob("dir1/[u-zU-Z]*/**/*.swift").map { $0.relative(to: temporaryDirectory).pathString }
        XCTAssertEqual(result, expected)
    }
}
