import Path
import ProjectDescription
import TestCoverageAttribution
import Testing
import TuistConfig

@testable import TuistLoader

@Suite(.coverageAttribution)
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

    @Test func from_mapsTheCoverageSelectiveTestingStrategy() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let manifest = ProjectDescription.Config(
            testInsights: .testInsights(
                coverage: .coverage(upload: true),
                selectiveTesting: .selectiveTesting(strategy: .coverage())
            ),
            project: .tuist(generationOptions: .options())
        )

        // When
        let got = try await TuistConfig.Tuist.from(manifest: manifest, rootDirectory: path, at: path)

        // Then
        #expect(got.testInsights.selectiveTesting == TuistConfig.Tuist.TestInsights.SelectiveTesting(strategy: .coverage))
    }

    @Test func from_leavesTheSelectiveTestingStrategyUnsetByDefault() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let manifest = ProjectDescription.Config(
            testInsights: .testInsights(selectiveTesting: .selectiveTesting()),
            project: .tuist(generationOptions: .options())
        )

        // When
        let got = try await TuistConfig.Tuist.from(manifest: manifest, rootDirectory: path, at: path)

        // Then
        #expect(got.testInsights.selectiveTesting == TuistConfig.Tuist.TestInsights.SelectiveTesting(strategy: nil))
    }

    @Test func from_requiresCoverageUploadForTheCoverageStrategy() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let manifest = ProjectDescription.Config(
            testInsights: .testInsights(
                coverage: .coverage(upload: false),
                selectiveTesting: .selectiveTesting(strategy: .coverage())
            ),
            project: .tuist(generationOptions: .options())
        )

        // When / Then
        await #expect(throws: ConfigManifestMapperError.coverageStrategyRequiresCoverageUpload) {
            try await TuistConfig.Tuist.from(manifest: manifest, rootDirectory: path, at: path)
        }
    }
}
