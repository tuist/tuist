import Foundation
import PathKit
@testable import xcbuddykit
import XCTest

final class ConfigTests: XCTestCase {
    var cache: MockGraphLoaderCache!
    var manifestLoader: MockGraphManifestLoader!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        cache = MockGraphLoaderCache()
        manifestLoader = MockGraphManifestLoader()
        fileHandler = MockFileHandler()
    }

    func test_read_returns_the_value_from_the_cache_if_it_exists() throws {
        let config = Config.testData()
        let path = Path("/path/to/config/folder")
        cache.configStub = { _path in
            (_path == path) ? config : nil
        }
        let got = try Config.read(path: path, manifestLoader: manifestLoader, cache: cache)
        XCTAssertTrue(config === got)
    }

    func test_read_throws_when_the_file_doesnt_exist() throws {
        let path = Path("/path/to/config/folder")
        var gotPath: Path?
        var gotError: Error?
        fileHandler.existsStub = { path in
            gotPath = path
            return false
        }
        do {
            _ = try Config.read(path: path,
                                manifestLoader: manifestLoader,
                                cache: cache,
                                fileHandler: fileHandler)
        } catch {
            gotError = error
        }
        let expectedPath = Path("/path/to/config/folder/\(Constants.Manifest.config)")
        XCTAssertEqual(gotPath, expectedPath)
        XCTAssertEqual(gotError as? GraphLoadingError, GraphLoadingError.missingFile(expectedPath))
    }

    func test_read_reads_the_value_from_the_manifest() throws {
        let path = Path("/path/to/config/folder")
        let manifestData: Data = try Data.testJson([:])
        var gotPath: Path?
        fileHandler.existsStub = { path in
            gotPath = path
            return true
        }
        manifestLoader.loadStub = { _ in
            manifestData
        }
        _ = try Config.read(path: path,
                            manifestLoader: manifestLoader,
                            cache: cache,
                            fileHandler: fileHandler)
        let expectedPath = Path("/path/to/config/folder/\(Constants.Manifest.config)")
        XCTAssertEqual(gotPath, expectedPath)
    }
}
