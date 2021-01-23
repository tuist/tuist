import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class LibraryMetadataProviderTests: XCTestCase {
    var subject: LibraryMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = LibraryMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loadMetadata() throws {
        // Given
        let libraryPath = fixturePath(path: RelativePath("libStaticLibrary.a"))

        // When
        let metadata = try subject.loadMetadata(at: libraryPath, publicHeaders: libraryPath.parentDirectory, swiftModuleMap: nil)

        // Then
        XCTAssertEqual(metadata, LibraryMetadata(
            path: libraryPath,
            publicHeaders: libraryPath.parentDirectory,
            swiftModuleMap: nil,
            architectures: [.x8664],
            linking: .static
        ))
    }
}
