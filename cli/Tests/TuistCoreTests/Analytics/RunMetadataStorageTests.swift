import XCTest
@testable import TuistCore

final class RunMetadataStorageTests: XCTestCase {
    func test_update_targetContentHashSubhashes_merges_with_existing_entries() async {
        // Given
        let storage = RunMetadataStorage()
        await storage.update(targetContentHashSubhashes: [
            "binary-hash": .test(sources: "binary-sources"),
        ])

        // When
        await storage.update(targetContentHashSubhashes: [
            "selective-hash": .test(sources: "selective-sources"),
        ])

        // Then
        let subhashes = await storage.targetContentHashSubhashes
        XCTAssertEqual(subhashes["binary-hash"]?.sources, "binary-sources")
        XCTAssertEqual(subhashes["selective-hash"]?.sources, "selective-sources")
    }

    func test_update_targetContentHashSubhashes_overwrites_same_hash_entries() async {
        // Given
        let storage = RunMetadataStorage()
        await storage.update(targetContentHashSubhashes: [
            "shared-hash": .test(sources: "old-sources"),
        ])

        // When
        await storage.update(targetContentHashSubhashes: [
            "shared-hash": .test(sources: "new-sources"),
        ])

        // Then
        let subhashes = await storage.targetContentHashSubhashes
        XCTAssertEqual(subhashes["shared-hash"]?.sources, "new-sources")
    }
}
