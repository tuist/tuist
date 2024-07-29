import Foundation
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

//  Inspired by: https://gist.github.com/efirestone/ce01ae109e08772647eb061b3bb387c3

final class GlobTests: TuistTestCase {
    let temporaryFiles = ["foo", "bar", "baz", "dir1/file1.ext", "dir1/dir2/dir3/file2.ext", "dir1/**(_:_:)/file3.ext"]
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()

        temporaryDirectory = try! temporaryPath().url
        try! createFiles(temporaryFiles, content: "")
    }

    private func test(pattern: String, behavior: Glob.Behavior, expected: [String]) {
        testWithPrefix("\(temporaryDirectory.path)/", pattern: pattern, behavior: behavior, expected: expected)

        let originalPath = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(temporaryDirectory.path)
        defer {
            FileManager.default.changeCurrentDirectoryPath(originalPath)
        }

        testWithPrefix("./", pattern: pattern, behavior: behavior, expected: expected)
    }

    private func testWithPrefix(_ prefix: String, pattern: String, behavior: Glob.Behavior, expected: [String]) {
        let glob = Glob(pattern: "\(prefix)\(pattern)", behavior: behavior)
        XCTAssertEqual(
            glob.paths,
            expected.map { "\(prefix)\($0)" },
            "pattern \"\(pattern)\" failed with prefix \"\(prefix)\""
        )
    }

    func testBraces() {
        let pattern = "\(temporaryDirectory.path)/ba{r,y,z}"
        let glob = Glob(pattern: pattern)
        var contents = [String]()
        for file in glob {
            contents.append(file)
        }
        XCTAssertEqual(contents, ["\(temporaryDirectory.path)/bar", "\(temporaryDirectory.path)/baz"], "matching with braces failed")
    }

    func testNothingMatches() {
        let pattern = "\(temporaryDirectory.path)/nothing"
        let glob = Glob(pattern: pattern)
        var contents = [String]()
        for file in glob {
            contents.append(file)
        }
        XCTAssertEqual(contents, [], "expected empty list of files")
    }

    func testDirectAccess() {
        let pattern = "\(temporaryDirectory.path)/ba{r,y,z}"
        let glob = Glob(pattern: pattern)
        XCTAssertEqual(glob.paths, ["\(temporaryDirectory.path)/bar", "\(temporaryDirectory.path)/baz"], "matching with braces failed")
    }

    func testIterateTwice() {
        let pattern = "\(temporaryDirectory.path)/ba{r,y,z}"
        let glob = Glob(pattern: pattern)
        var contents1 = [String]()
        var contents2 = [String]()
        for file in glob {
            contents1.append(file)
        }
        let filesAfterOnce = glob.paths
        for file in glob {
            contents2.append(file)
        }
        XCTAssertEqual(contents1, contents2, "results for calling for-in twice are the same")
        XCTAssertEqual(glob.paths, filesAfterOnce, "calling for-in twice doesn't only memoizes once")
    }

    func testIndexing() {
        let pattern = "\(temporaryDirectory.path)/ba{r,y,z}"
        let glob = Glob(pattern: pattern)
        guard glob.count == 2 else {
            return XCTFail("Exptected 2 results")
        }
        XCTAssertEqual(glob[0], "\(temporaryDirectory.path)/bar", "indexing")
    }

    // MARK: - Globstar - Bash v3

    func testGlobstarBashV3NoSlash() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**"
        test(
            pattern: "**",
            behavior: GlobBehaviorBashV3,
            expected: ["bar", "baz", "dir1/", "foo"]
        )
    }

    func testGlobstarBashV3WithSlash() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**/"
        test(
            pattern: "**/",
            behavior: GlobBehaviorBashV3,
            expected: ["dir1/"]
        )
    }

    func testGlobstarBashV3WithSlashAndWildcard() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**/*"
        test(
            pattern: "**/*",
            behavior: GlobBehaviorBashV3,
            expected: ["dir1/**(_:_:)/", "dir1/dir2/", "dir1/file1.ext"]
        )
    }

    func testPatternEndsWithGlobstarBashV3() {
        test(
            pattern: "dir1/**",
            behavior: GlobBehaviorBashV3,
            expected: [
                "dir1/**(_:_:)/",
                "dir1/dir2/",
                "dir1/file1.ext",
            ]
        )
    }

    func testDoubleGlobstarBashV3() {
        test(
            pattern: "**/dir2/**/*",
            behavior: GlobBehaviorBashV3,
            expected: ["dir1/dir2/dir3/file2.ext"]
        )
    }

    // MARK: - Globstar - Bash v4

    func testGlobstarBashV4NoSlash() {
        // Should be the equivalent of "ls -d -1 /(temporaryDirectory)/**"
        test(
            pattern: "**",
            behavior: GlobBehaviorBashV4,
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
            behavior: GlobBehaviorBashV4,
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
            behavior: GlobBehaviorBashV4,
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
            behavior: GlobBehaviorBashV4,
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
            behavior: GlobBehaviorBashV4,
            expected: [
                "dir1/dir2/dir3/",
                "dir1/dir2/dir3/file2.ext",
            ]
        )
    }

    // MARK: - Globstar - Gradle

    func testGlobstarGradleNoSlash() {
        // Should be the equivalent of
        // FileTree tree = project.fileTree((Object)'/tmp') {
        //   include 'glob-test.7m0Lp/**'
        // }
        //
        // Note that the sort order currently matches Bash and not Gradle
        test(
            pattern: "**",
            behavior: GlobBehaviorGradle,
            expected: [
                "bar",
                "baz",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
                "foo",
            ]
        )
    }

    func testGlobstarGradleWithSlash() {
        // Should be the equivalent of
        // FileTree tree = project.fileTree((Object)'/tmp') {
        //   include 'glob-test.7m0Lp/**/'
        // }
        //
        // Note that the sort order currently matches Bash and not Gradle
        test(
            pattern: "**/",
            behavior: GlobBehaviorGradle,
            expected: [
                "bar",
                "baz",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
                "foo",
            ]
        )
    }

    func testGlobstarGradleWithSlashAndWildcard() {
        // Should be the equivalent of
        // FileTree tree = project.fileTree((Object)'/tmp') {
        //   include 'glob-test.7m0Lp/**/*'
        // }
        //
        // Note that the sort order currently matches Bash and not Gradle
        test(
            pattern: "**/*",
            behavior: GlobBehaviorGradle,
            expected: [
                "bar",
                "baz",
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
                "foo",
            ]
        )
    }

    func testPatternEndsWithGlobstarGradle() {
        test(
            pattern: "dir1/**",
            behavior: GlobBehaviorGradle,
            expected: [
                "dir1/**(_:_:)/file3.ext",
                "dir1/dir2/dir3/file2.ext",
                "dir1/file1.ext",
            ]
        )
    }

    func testDoubleGlobstarGradle() {
        // Should be the equivalent of
        // FileTree tree = project.fileTree((Object)'/tmp') {
        //   include 'glob-test.7m0Lp/**/dir2/**/*'
        // }
        //
        // Note that the sort order currently matches Bash and not Gradle
        test(
            pattern: "**/dir2/**/*",
            behavior: GlobBehaviorGradle,
            expected: [
                "dir1/dir2/dir3/file2.ext",
            ]
        )
    }
}
