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
        try createFiles(temporaryFiles, content: "")
    }

    private func test(pattern: String, expected: [String]) {
        testWithPrefix("\(temporaryDirectory.url.path)/", pattern: pattern, expected: expected)

        let originalPath = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(temporaryDirectory.url.path)
        defer {
            FileManager.default.changeCurrentDirectoryPath(originalPath)
        }

        testWithPrefix("./", pattern: pattern, expected: expected)
    }

    private func testWithPrefix(_ prefix: String, pattern: String, expected: [String]) {
        let glob = Glob(pattern: "\(prefix)\(pattern)")
        XCTAssertEqual(
            glob.paths,
            expected.map { "\(prefix)\($0)" },
            "pattern \"\(pattern)\" failed with prefix \"\(prefix)\""
        )
    }

    func testNothingMatches() {
        let pattern = "nothing"
        XCTAssertEmpty(temporaryDirectory.glob(pattern))
    }

    func testBraces() {
        let pattern = "ba{r,y,z}"
        XCTAssertEqual(
            temporaryDirectory.glob(pattern),
            [temporaryDirectory.appending(component: "bar"), temporaryDirectory.appending(component: "baz")]
        )
    }

    // MARK: - Globstar - Bash v4

    func testGlobstarBashV4NoSlash() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**"
        test(
            pattern: "**",
            expected: [
                "",
                "bar",
                "baz",
                "dir1/",
                "dir1/**(_:_:)/",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/",
                "dir1/dir2/dir3/",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
                "foo",
            ]
        )
    }

    func testGlobstarBashV4WithSlash() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**/"
        test(
            pattern: "**/",
            expected: [
                "",
                "dir1/",
                "dir1/**(_:_:)/",
                "dir1/dir2/",
                "dir1/dir2/dir3/",
            ]
        )
    }

    func testGlobstarBashV4WithSlashAndWildcard() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**/*"
        test(
            pattern: "**/*",
            expected: [
                "bar",
                "baz",
                "dir1/",
                "dir1/**(_:_:)/",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/",
                "dir1/dir2/dir3/",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
                "foo",
            ]
        )
    }

    func testPatternEndsWithGlobstarBashV4() {
        test(
            pattern: "dir1/**",
            expected: [
                "dir1/",
                "dir1/**(_:_:)/",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/",
                "dir1/dir2/dir3/",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
            ]
        )
    }

    func testDoubleGlobstarBashV4() {
        test(
            pattern: "**/dir2/**/*",
            expected: [
                "dir1/dir2/dir3/",
                "dir1/dir2/dir3/file2.ext",
            ]
        )
    }

}
