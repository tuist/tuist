import Path
import ProjectDescription
import Testing
import TuistConfig

@testable import TuistLoader

struct TuistManifestMapperTests {
    @Test func from_mapsTheXcodeCacheStoreSizeLimitToBytes() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let manifest = ProjectDescription.Config(
            xcodeCache: .xcodeCache(upload: false, storeSizeLimit: .gigabytes(20)),
            project: .tuist(generationOptions: .options())
        )

        // When
        let got = try await TuistConfig.Tuist.from(manifest: manifest, rootDirectory: path, at: path)

        // Then
        #expect(got.xcodeCache == TuistConfig.Tuist.XcodeCache(upload: false, storeSizeLimit: 21_474_836_480))
    }

    @Test func from_leavesTheXcodeCacheStoreSizeLimitUnsetByDefault() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let manifest = ProjectDescription.Config(project: .tuist(generationOptions: .options()))

        // When
        let got = try await TuistConfig.Tuist.from(manifest: manifest, rootDirectory: path, at: path)

        // Then
        #expect(got.xcodeCache.storeSizeLimit == nil)
    }
}
