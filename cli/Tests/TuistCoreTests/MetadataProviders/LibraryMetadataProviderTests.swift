import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistTesting

struct LibraryMetadataProviderTests {
    let subject: LibraryMetadataProvider

    init() {
        subject = LibraryMetadataProvider()
    }

    @Test func test_loadMetadata() async throws {
        // Given
        let libraryPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "libStaticLibrary.a"))

        // When
        let metadata = try await subject.loadMetadata(
            at: libraryPath,
            publicHeaders: libraryPath.parentDirectory,
            swiftModuleMap: nil
        )

        // Then
        #expect(metadata == LibraryMetadata(
            path: libraryPath,
            publicHeaders: libraryPath.parentDirectory,
            swiftModuleMap: nil,
            architectures: [.x8664],
            linking: .static
        ))
    }
}
