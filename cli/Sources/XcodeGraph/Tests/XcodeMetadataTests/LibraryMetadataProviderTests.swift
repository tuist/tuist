import Path
import Testing
import XcodeGraph
@testable import XcodeMetadata

@Suite
struct LibraryMetadataProviderTests {
    var subject: LibraryMetadataProvider

    /// Initializes the test suite, setting up the required `LibraryMetadataProvider` instance.
    init() {
        subject = LibraryMetadataProvider()
    }

    @Test
    func loadMetadata() async throws {
        // Given
        let libraryPath = AssertionsTesting.fixturePath(path: try RelativePath(validating: "libStaticLibrary.a"))

        // When
        let metadata = try await subject.loadMetadata(
            at: libraryPath,
            publicHeaders: libraryPath.parentDirectory,
            swiftModuleMap: nil
        )

        // Then
        #expect(
            metadata == LibraryMetadata(
                path: libraryPath,
                publicHeaders: libraryPath.parentDirectory,
                swiftModuleMap: nil,
                architectures: [.x8664],
                linking: .static
            ),
            "Loaded metadata does not match expected metadata"
        )
    }
}
