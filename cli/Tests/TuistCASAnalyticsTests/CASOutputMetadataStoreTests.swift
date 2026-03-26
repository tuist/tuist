import Foundation
import Testing
import TuistEnvironment
import TuistTesting
@testable import TuistCASAnalytics

struct CASOutputMetadataStoreTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_and_retrieve() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        let subject = CASOutputMetadataStore(database: database)

        let metadata = CASOutputMetadata(size: 1024, duration: 5.333, compressedSize: 512)
        try await subject.storeMetadata(metadata, for: "test-cas-id")

        let result = try #require(try await subject.metadata(for: "test-cas-id"))
        #expect(result.size == 1024)
        #expect(result.duration == 5.333)
        #expect(result.compressedSize == 512)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func metadata_returns_nil_when_not_stored() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        let subject = CASOutputMetadataStore(database: database)

        let result = try await subject.metadata(for: "nonexistent")
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_overwrites_existing() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        let subject = CASOutputMetadataStore(database: database)

        try await subject.storeMetadata(CASOutputMetadata(size: 100, duration: 1.0, compressedSize: 50), for: "key")
        try await subject.storeMetadata(CASOutputMetadata(size: 200, duration: 2.0, compressedSize: 100), for: "key")

        let result = try #require(try await subject.metadata(for: "key"))
        #expect(result.size == 200)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeMetadata_sanitizes_cas_id() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        let subject = CASOutputMetadataStore(database: database)

        try await subject.storeMetadata(CASOutputMetadata(size: 1, duration: 1.0, compressedSize: 1), for: "test/cas:id~special")
        let result = try await subject.metadata(for: "test/cas:id~special")
        #expect(result != nil)
    }
}
