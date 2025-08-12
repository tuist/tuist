import FileSystem
import Foundation
import Mockable
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class ResourcesContentHasherTests: TuistUnitTestCase {
    private var subject: ResourcesContentHasher!
    private var contentHasher: ContentHasher!

    override func setUp() {
        super.setUp()
        contentHasher = ContentHasher()
        subject = ResourcesContentHasher(contentHasher: contentHasher)
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    func test_hash_is_deterministic() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let fileSystem = FileSystem()
        let resource1 = temporaryDirectory.appending(component: "1.png")
        let resource2 = temporaryDirectory.appending(component: "referenced-folder").appending(component: "2.png")
        try await fileSystem.makeDirectory(at: resource2.parentDirectory)
        try await fileSystem.writeText("1", at: resource1)
        try await fileSystem.writeText("2", at: resource2)
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )
        let resourceFileElements = ResourceFileElements([
            .file(path: resource1, tags: ["tag1"], inclusionCondition: .when(Set([.macos]))),
            .folderReference(path: resource2.parentDirectory, tags: ["tag2"], inclusionCondition: .when(Set([.ios]))),
        ], privacyManifest: privacyManifest)
        var hashes: Set<String> = Set()

        // When
        for _ in 0 ..< 100 {
            hashes.insert(try await subject.hash(identifier: "resources", resources: resourceFileElements).hash)
        }

        // Then
        XCTAssertEqual(hashes.count, 1)
    }

    func test_hash_changes_after_resource_rename() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let fileSystem = FileSystem()
        let resource1 = temporaryDirectory.appending(component: "1.png")
        let resource2 = temporaryDirectory.appending(component: "2.png")
        try await fileSystem.writeText("1", at: resource1)
        try await fileSystem.writeText("1", at: resource2)
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )
        let resourceFileElements1 = ResourceFileElements([
            .file(path: resource1),
        ], privacyManifest: privacyManifest)
        let resourceFileElements2 = ResourceFileElements([
            .file(path: resource2),
        ], privacyManifest: privacyManifest)

        // When
        let hash1 = try await subject.hash(identifier: "resources", resources: resourceFileElements1).hash
        let hash2 = try await subject.hash(identifier: "resources", resources: resourceFileElements2).hash

        // Then
        XCTAssertNotEqual(hash1, hash2)
    }

    func test_hash_returnsTheRightMerkleNode() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let fileSystem = FileSystem()
        let resource1 = temporaryDirectory.appending(component: "1.png")
        let resource2 = temporaryDirectory.appending(component: "referenced-folder").appending(component: "2.png")
        try await fileSystem.makeDirectory(at: resource2.parentDirectory)
        try await fileSystem.writeText("1", at: resource1)
        try await fileSystem.writeText("2", at: resource2)
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )
        let resourceFileElements = ResourceFileElements([
            .file(path: resource1, tags: ["tag1"], inclusionCondition: .when(Set([.macos]))),
            .folderReference(path: resource2.parentDirectory, tags: ["tag2"], inclusionCondition: .when(Set([.ios]))),
        ], privacyManifest: privacyManifest)

        // When
        let got = try await subject.hash(identifier: "resources", resources: resourceFileElements)

        // Then
        XCTAssertEqual(got, MerkleNode(
            hash: "b310dc618b8893abc76c9a4b9628e04e",
            identifier: "resources",
            children: [
                MerkleNode(
                    hash: "e297e7925b4d0d805f87eb8842081511",
                    identifier: resource1.pathString,
                    children: [
                        MerkleNode(
                            hash: "4a47a0db6e60853dedfcfdf08a5ca249",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "content",
                            children: []
                        ),
                        MerkleNode(
                            hash: "cfcd208495d565ef66e7dff9f98764da",
                            identifier: "isReference",
                            children: []
                        ),
                        MerkleNode(
                            hash: "e9bae3ce1d7ac00b0b1aa2fbddc50cfb",
                            identifier: "tags",
                            children: []
                        ),
                        MerkleNode(
                            hash: "4ed91b7e02b960dc31256de17f3f131f",
                            identifier: "inclusionCondition",
                            children: [
                                MerkleNode(
                                    hash: "43b9d8ea18c48c3a64c4e37338fc668f",
                                    identifier: "macos",
                                    children: []
                                ),
                            ]
                        ),
                    ]
                ),
                MerkleNode(
                    hash: "67a89904e984196e4081300ca5cfa0fa",
                    identifier: resource2.parentDirectory.pathString,
                    children: [
                        MerkleNode(
                            hash: "129ccb8ef5914163bbcc42da1658d73f",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c81e728d9d4c2f636f067f89cc14862c",
                            identifier: "content",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "isReference",
                            children: []
                        ),
                        MerkleNode(
                            hash: "f32af7d8e6b19f67a63af85e5e7b8a82",
                            identifier: "tags",
                            children: []
                        ),
                        MerkleNode(
                            hash: "12ee3b51be5e4bd87bf7a4c8895cc088",
                            identifier: "inclusionCondition",
                            children: [
                                MerkleNode(
                                    hash: "9e304d4e8df1b74cfa009913198428ab",
                                    identifier: "ios",
                                    children: []
                                ),
                            ]
                        ),
                    ]
                ),
                MerkleNode(
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
                ),
            ]
        ))
    }
}
