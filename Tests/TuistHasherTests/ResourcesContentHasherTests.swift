import FileSystem
import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
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
        for i in 0 ..< 100 {
            hashes.insert(try subject.hash(identifier: "resources", resources: resourceFileElements).hash)
        }

        // Then
        XCTAssertEqual(hashes.count, 1)
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
        let got = try subject.hash(identifier: "resources", resources: resourceFileElements)

        // Then
        XCTAssertEqual(got, MerkleNode(
            hash: "93fdd9b5838add3a2b695d6d07389ca6",
            identifier: "resources",
            children: [
                MerkleNode(
                    hash: "c4ca4238a0b923820dcc509a6f75849b",
                    identifier: resource1.pathString,
                    children: []
                ),
                MerkleNode(
                    hash: "c81e728d9d4c2f636f067f89cc14862c",
                    identifier: resource2.parentDirectory.pathString,
                    children: []
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
