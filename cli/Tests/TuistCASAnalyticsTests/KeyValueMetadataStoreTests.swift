import Foundation
import Testing
import TuistEnvironment
import TuistTesting
@testable import TuistCASAnalytics

struct KeyValueMetadataStoreTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_and_retrieve_read_operation() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open(stateDirectory: mockEnvironment.stateDirectory)
        let subject = KeyValueMetadataStore(database: database)

        try await subject.storeMetadata(KeyValueMetadata(duration: 5.333), for: "test-key", operationType: .read)

        let result = try #require(try await subject.metadata(for: "test-key", operationType: .read))
        #expect(result.duration == 5.333)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_and_retrieve_write_operation() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open(stateDirectory: mockEnvironment.stateDirectory)
        let subject = KeyValueMetadataStore(database: database)

        try await subject.storeMetadata(KeyValueMetadata(duration: 3.25), for: "test-key", operationType: .write)

        let result = try #require(try await subject.metadata(for: "test-key", operationType: .write))
        #expect(result.duration == 3.25)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func read_and_write_operations_are_separate() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open(stateDirectory: mockEnvironment.stateDirectory)
        let subject = KeyValueMetadataStore(database: database)

        try await subject.storeMetadata(KeyValueMetadata(duration: 1.0), for: "key", operationType: .read)
        try await subject.storeMetadata(KeyValueMetadata(duration: 2.0), for: "key", operationType: .write)

        let readResult = try #require(try await subject.metadata(for: "key", operationType: .read))
        let writeResult = try #require(try await subject.metadata(for: "key", operationType: .write))
        #expect(readResult.duration == 1.0)
        #expect(writeResult.duration == 2.0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_nil_when_not_stored() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open(stateDirectory: mockEnvironment.stateDirectory)
        let subject = KeyValueMetadataStore(database: database)

        let result = try await subject.metadata(for: "nonexistent", operationType: .read)
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_sanitizes_cache_key() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open(stateDirectory: mockEnvironment.stateDirectory)
        let subject = KeyValueMetadataStore(database: database)

        try await subject.storeMetadata(KeyValueMetadata(duration: 5.0), for: "test/cache:key~special", operationType: .read)
        let result = try await subject.metadata(for: "test/cache:key~special", operationType: .read)
        #expect(result != nil)
    }
}
