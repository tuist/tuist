import Path
import Testing
import XcodeGraph
import XcodeMetadata

@Suite
struct FrameworkMetadataProviderTests {
    var subject: FrameworkMetadataProvider

    init() {
        subject = FrameworkMetadataProvider()
    }

    @Test
    func loadMetadata() async throws {
        // Given
        let frameworkPath = AssertionsTesting.fixturePath(path: try RelativePath(validating: "xpm.framework"))

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedBinaryPath = frameworkPath.appending(component: frameworkPath.basenameWithoutExt)
        let expectedDsymPath = frameworkPath.parentDirectory.appending(component: "xpm.framework.dSYM")

        #expect(
            metadata == FrameworkMetadata(
                path: frameworkPath,
                binaryPath: expectedBinaryPath,
                dsymPath: expectedDsymPath,
                bcsymbolmapPaths: [],
                linking: .dynamic,
                architectures: [.x8664, .arm64],
                status: .required
            ),
            "Loaded metadata does not match expected metadata"
        )
    }
}
