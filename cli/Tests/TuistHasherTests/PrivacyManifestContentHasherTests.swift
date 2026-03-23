import Foundation
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing
@testable import TuistHasher

struct PrivacyManifestContentHasherTests {
    private let subject: PrivacyManifestContentHasher
    init() {
        subject = PrivacyManifestContentHasher(contentHasher: ContentHasher())
    }


    @Test
    func test_hash_isDeterministic() throws {
        // Given
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )
        var results: Set<String> = Set()

        // When
        for _ in 0 ... 100 {
            results.insert(try subject.hash(identifier: "privacyManifest", privacyManifest: privacyManifest).hash)
        }

        // Then
        #expect(results.count == 1)
    }

    @Test
    func test_hash_returnsACorrectMerkleNode() throws {
        // Given
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )

        // When
        let got = try subject.hash(identifier: "privacyManifest", privacyManifest: privacyManifest)

        // Then
        #expect(got == MerkleNode(
            hash: "bdb8825693f6a3fef832665ef7b93d14",
            identifier: "privacyManifest",
            children: [
                MerkleNode(
                    hash: "c4ca4238a0b923820dcc509a6f75849b",
                    identifier: "tracking",
                    children: []
                ),
                MerkleNode(
                    hash: "fb24174794a54483a3c3bdb2ce3dde75",
                    identifier: "trackingDomains",
                    children: []
                ),
                MerkleNode(
                    hash: "18f8dcf557f61dc3c1cd766f1245c130",
                    identifier: "collectedDataTypes",
                    children: []
                ),
                MerkleNode(
                    hash: "18f8dcf557f61dc3c1cd766f1245c130",
                    identifier: "accessedApiTypes",
                    children: []
                ),
            ]
        ))
    }
}
