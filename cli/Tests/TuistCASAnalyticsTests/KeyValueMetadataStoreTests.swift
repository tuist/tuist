import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting
@testable import TuistCASAnalytics

struct KeyValueMetadataStoreTests {
    private let fileSystem = FileSystem()
    private let subject = KeyValueMetadataStore()

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_creates_directory_and_stores_metadata_for_read_operation() async throws {
        let cacheKey = "test-cache-key"
        let metadata = KeyValueMetadata(duration: 5.333)

        try await subject.storeMetadata(metadata, for: cacheKey, operationType: .read)

        let keyValueDirectory = Environment.current.stateDirectory
            .appending(component: "keyvalue")
            .appending(component: "read")
        let metadataFilePath = keyValueDirectory.appending(component: "test-cache-key.json")

        #expect(try await fileSystem.exists(keyValueDirectory))
        #expect(try await fileSystem.exists(metadataFilePath))

        let jsonContent = try await fileSystem.readTextFile(at: metadataFilePath)
        #expect(jsonContent.contains("\"duration\":5.333"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_creates_directory_and_stores_metadata_for_write_operation() async throws {
        let cacheKey = "test-cache-key"
        let metadata = KeyValueMetadata(duration: 3.25)

        try await subject.storeMetadata(metadata, for: cacheKey, operationType: .write)

        let keyValueDirectory = Environment.current.stateDirectory
            .appending(component: "keyvalue")
            .appending(component: "write")
        let metadataFilePath = keyValueDirectory.appending(component: "test-cache-key.json")

        #expect(try await fileSystem.exists(keyValueDirectory))
        #expect(try await fileSystem.exists(metadataFilePath))

        let jsonContent = try await fileSystem.readTextFile(at: metadataFilePath)
        #expect(jsonContent.contains("\"duration\":3.25"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_sanitizes_cache_key() async throws {
        let cacheKey = "test/cache:key~with/special:chars"
        let metadata = KeyValueMetadata(duration: 5.0)

        try await subject.storeMetadata(metadata, for: cacheKey, operationType: .read)

        let keyValueDirectory = Environment.current.stateDirectory
            .appending(component: "keyvalue")
            .appending(component: "read")
        let expectedPath = keyValueDirectory.appending(component: "test_cache_key_with_special_chars.json")

        #expect(try await fileSystem.exists(expectedPath))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_nil_when_file_does_not_exist() async throws {
        let cacheKey = "nonexistent-cache-key"

        let result = try await subject.metadata(for: cacheKey, operationType: .read)

        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_decoded_metadata_for_read_operation() async throws {
        let cacheKey = "test-cache-key"
        let metadata = KeyValueMetadata(duration: 7.5)

        try await subject.storeMetadata(metadata, for: cacheKey, operationType: .read)

        let result = try await subject.metadata(for: cacheKey, operationType: .read)

        let retrievedMetadata = try #require(result)
        #expect(retrievedMetadata.duration == 7.5)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_decoded_metadata_for_write_operation() async throws {
        let cacheKey = "test-cache-key"
        let metadata = KeyValueMetadata(duration: 12.8)

        try await subject.storeMetadata(metadata, for: cacheKey, operationType: .write)

        let result = try await subject.metadata(for: cacheKey, operationType: .write)

        let retrievedMetadata = try #require(result)
        #expect(retrievedMetadata.duration == 12.8)
    }
}
