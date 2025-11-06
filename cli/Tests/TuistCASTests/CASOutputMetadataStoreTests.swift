import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting
@testable import TuistCASAnalytics

struct CASOutputMetadataStoreTests {
    private let fileSystem = FileSystem()
    private let subject = CASOutputMetadataStore()

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_creates_directory_and_stores_metadata() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.stateDirectory = temporaryDirectory

        let casID = "test-cas-id"
        let metadata = CASOutputMetadata(
            size: 1024,
            duration: 5.333,
            compressedSize: 512
        )

        // When
        try await subject.storeMetadata(metadata, for: casID)

        // Then
        let casDirectory = temporaryDirectory.appending(component: "cas")
        let metadataFilePath = casDirectory.appending(component: "test-cas-id.json")

        #expect(try await fileSystem.exists(casDirectory))
        #expect(try await fileSystem.exists(metadataFilePath))

        let jsonContent = try await fileSystem.readTextFile(at: metadataFilePath)
        #expect(jsonContent.contains("\"size\":1024"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_sanitizes_cas_id() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.stateDirectory = temporaryDirectory

        let casID = "test/cas:id~with/special:chars"
        let metadata = CASOutputMetadata(
            size: 1024,
            duration: 5.0,
            compressedSize: 512
        )

        // When
        try await subject.storeMetadata(metadata, for: casID)

        // Then
        let casDirectory = temporaryDirectory.appending(component: "cas")
        let expectedPath = casDirectory.appending(component: "test_cas_id_with_special_chars.json")

        #expect(try await fileSystem.exists(expectedPath))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_nil_when_file_does_not_exist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.stateDirectory = temporaryDirectory

        let casID = "nonexistent-cas-id"

        // When
        let result = try await subject.metadata(for: casID)

        // Then
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_decoded_metadata_when_file_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.stateDirectory = temporaryDirectory

        let casID = "test-cas-id"
        let metadata = CASOutputMetadata(
            size: 2048,
            duration: 5.333,
            compressedSize: 1024
        )

        // First store the metadata
        try await subject.storeMetadata(metadata, for: casID)

        // When
        let result = try await subject.metadata(for: casID)

        // Then
        let retrievedMetadata = try #require(result)
        #expect(retrievedMetadata.size == 2048)
        #expect(retrievedMetadata.compressedSize == 1024)
        #expect(retrievedMetadata.duration == 5.333)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_and_metadata_roundtrip() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.stateDirectory = temporaryDirectory

        let casID = "roundtrip-test"
        let originalMetadata = CASOutputMetadata(
            size: 4096,
            duration: 9.334,
            compressedSize: 2048
        )

        // When
        try await subject.storeMetadata(originalMetadata, for: casID)
        let retrievedMetadata = try await subject.metadata(for: casID)

        // Then
        let metadata = try #require(retrievedMetadata)
        #expect(metadata.size == originalMetadata.size)
    }
}
