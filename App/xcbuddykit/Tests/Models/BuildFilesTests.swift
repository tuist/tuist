import Foundation
import PathKit
import Unbox
@testable import xcbuddykit
import XCTest

final class BuildFilesTests: XCTestCase {
    var context: GraphLoaderContext!
    var manifestLoading: MockGraphManifestLoader!
    var cache: MockGraphLoaderCache!
    var projectPath: Path!
    var fileHandler: MockFileHandler!

    override func setUp() {
        manifestLoading = MockGraphManifestLoader()
        cache = MockGraphLoaderCache()
        projectPath = Path("/test/")
        fileHandler = MockFileHandler()
        context = GraphLoaderContext.test(manifestLoading: manifestLoading,
                                          cache: cache,
                                          projectPath: projectPath,
                                          fileHandler: fileHandler)
    }

    func test_init_returns_the_right_value_when_include() throws {
        let dictionary: [String: Any] = [
            "type": "include",
            "paths": ["path/**/*.swift"],
        ]
        let unboxer = Unboxer(dictionary: dictionary)
        let got = try BuildFiles(unboxer: unboxer)
        XCTAssertEqual(got, .include([Path("path/**/*.swift")]))
    }

    func test_init_returns_the_right_value_when_exclude() throws {
        let dictionary: [String: Any] = [
            "type": "exclude",
            "paths": ["path/**/*.swift"],
        ]

        let unboxer = Unboxer(dictionary: dictionary)
        let got = try BuildFiles(unboxer: unboxer)
        XCTAssertEqual(got, .exclude([Path("path/**/*.swift")]))
    }

    func test_array_list_returns_the_right_value() {
        let array: [BuildFiles] = [
            BuildFiles.include(["path/include"]),
            BuildFiles.exclude(["path/exclude"]),
        ]
        fileHandler.globStub = { path, _ in
            if path == "path/include" {
                return ["/path/a.swift", "/path/b.swift"]
            } else if path == "path/exclude" {
                return ["/path/b.swift"]
            }
            return []
        }
        XCTAssertEqual(array.list(context: context), Set(Path("/path/a.swift")))
    }
}
