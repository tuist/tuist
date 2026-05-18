import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class SourceFilesContentHasherTests: TuistUnitTestCase {
    private var subject: SourceFilesContentHasher!
    private var sourceFile1Path: AbsolutePath!
    private var sourceFile2Path: AbsolutePath!

    override func setUp() async throws {
        try await super.setUp()
        let contentHasher = ContentHasher()
        let platformConditionContentHasher = PlatformConditionContentHasher(contentHasher: contentHasher)
        subject = SourceFilesContentHasher(
            contentHasher: contentHasher,
            platformConditionContentHasher: platformConditionContentHasher
        )
        let temporaryDir = try temporaryPath()
        sourceFile1Path = temporaryDir.appending(component: "sourceFile1")
        sourceFile2Path = temporaryDir.appending(component: "sourceFile2")
    }

    override func tearDown() {
        sourceFile1Path = nil
        sourceFile2Path = nil
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_when_sourcesHaveAHashSet() async throws {
        // Given
        let sourceFile1 = SourceFile(path: sourceFile1Path, contentHash: "first")
        let sourceFile2 = SourceFile(path: sourceFile2Path, contentHash: "second")

        // When
        let node = try await subject.hash(identifier: "sources", sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(node, MerkleNode(
            hash: "509478874af8f071e65a63e9b94a9195",
            identifier: "sources",
            children: [
                MerkleNode(
                    hash: "22e39be4aa826c549fc08dc3e1a1804f",
                    identifier: sourceFile1.path.pathString,
                    children: [
                        MerkleNode(
                            hash: "082b4a6d39b5f89e0c48bac6bc6c157b",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "first",
                            identifier: "content",
                            children: []
                        ),
                    ]
                ),
                MerkleNode(
                    hash: "d934c9824bcb5eddda91271229e7237b",
                    identifier: sourceFile2.path.pathString,
                    children: [
                        MerkleNode(
                            hash: "ea109ebc1d271b006a1e76824e55df15",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "second",
                            identifier: "content",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }

    func test_hash_when_sourcesHaveNoHashSet() async throws {
        // Given
        let sourceFile1 = SourceFile(
            path: sourceFile1Path,
            compilerFlags: "-fno-objc-arc;",
            codeGen: .public,
            compilationCondition: .when(Set([.macos]))
        )
        let sourceFile2 = SourceFile(
            path: sourceFile2Path,
            codeGen: .private
        )
        try await fileSystem.writeText("sourceFile1", at: sourceFile1Path)
        try await fileSystem.writeText("sourceFile2", at: sourceFile2Path)

        // When
        let node = try await subject.hash(identifier: "sources", sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(node, MerkleNode(
            hash: "36e193e29391e3f9e113b8b0e648d5f8",
            identifier: "sources",
            children: [
                MerkleNode(
                    hash: "62b16fd213fa4b1f0eeb23dee9badf4e",
                    identifier: sourceFile1Path.pathString,
                    children: [
                        MerkleNode(
                            hash: "082b4a6d39b5f89e0c48bac6bc6c157b",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "082b4a6d39b5f89e0c48bac6bc6c157b",
                            identifier: "content",
                            children: []
                        ),
                        MerkleNode(
                            hash: "b093fb8232ffd7d7696b9805744f1881",
                            identifier: "compilerFlags",
                            children: []
                        ),
                        MerkleNode(
                            hash: "574f02bf81a557f25b5346e071cbaef8",
                            identifier: "codeGen",
                            children: []
                        ),
                        MerkleNode(
                            hash: "4ed91b7e02b960dc31256de17f3f131f",
                            identifier: "compilationCondition",
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
                    hash: "86aef10de761e9c61c6a559bae571185",
                    identifier: sourceFile2Path.pathString,
                    children: [
                        MerkleNode(
                            hash: "ea109ebc1d271b006a1e76824e55df15",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "ea109ebc1d271b006a1e76824e55df15",
                            identifier: "content",
                            children: []
                        ),
                        MerkleNode(
                            hash: "11d51689d805daf9b5d2ecd0ca11c863",
                            identifier: "codeGen",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }

    func test_hash_changes_when_source_file_is_renamed() async throws {
        // Given
        let originalPath = sourceFile1Path!
        let renamedPath = originalPath.parentDirectory.appending(component: "renamedSourceFile")
        try await fileSystem.writeText("identical-content", at: originalPath)
        try await fileSystem.writeText("identical-content", at: renamedPath)

        let original = SourceFile(path: originalPath)
        let renamed = SourceFile(path: renamedPath)

        // When
        let originalHash = try await subject.hash(identifier: "sources", sources: [original]).hash
        let renamedHash = try await subject.hash(identifier: "sources", sources: [renamed]).hash

        // Then
        XCTAssertNotEqual(
            originalHash,
            renamedHash,
            "Renaming a source file with identical content must produce a different hash so selective testing reruns tests whose snapshots/fixtures key off the source file name."
        )
    }

    func test_hash_changes_when_source_file_is_renamed_with_preset_content_hash() async throws {
        // Given
        let originalPath = sourceFile1Path!
        let renamedPath = originalPath.parentDirectory.appending(component: "renamedSourceFile")
        let original = SourceFile(path: originalPath, contentHash: "shared")
        let renamed = SourceFile(path: renamedPath, contentHash: "shared")

        // When
        let originalHash = try await subject.hash(identifier: "sources", sources: [original]).hash
        let renamedHash = try await subject.hash(identifier: "sources", sources: [renamed]).hash

        // Then
        XCTAssertNotEqual(originalHash, renamedHash)
    }
}
