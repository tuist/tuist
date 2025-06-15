import Path
import XcodeGraph
import XCTest
@testable import TuistCore
@testable import TuistTesting

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

    func test_loadMetadata() async throws {
        // Given
        let libraryPath = fixturePath(path: try RelativePath(validating: "libStaticLibrary.a"))

        // When
        let metadata = try await subject.loadMetadata(
            at: libraryPath,
            publicHeaders: libraryPath.parentDirectory,
            swiftModuleMap: nil
        )

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
