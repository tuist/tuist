import FileSystem
import Foundation
import Mockable
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class CopyFilesContentHasherTests: TuistUnitTestCase {
    private var subject: CopyFilesContentHasher!

    override func setUp() {
        super.setUp()
        let contentHasher = ContentHasher()
        subject = CopyFilesContentHasher(
            contentHasher: contentHasher,
            platformConditionContentHasher: PlatformConditionContentHasher(contentHasher: contentHasher)
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_isDeterministicAcrossRuns() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let filePath = temporaryDirectory.appending(component: "file")
        try await fileSystem.touch(filePath)
        let copyFilesAction = CopyFilesAction(
            name: "action",
            destination: .resources,
            subpath: "sub-directory",
            files: [
                CopyFileElement.file(
                    path: filePath,
                    condition: .when(Set([.macos])),
                    codeSignOnCopy: true
                ),
            ]
        )
        var results: Set<String> = Set()

        // When
        for _ in 0 ... 100 {
            results.insert(try await subject.hash(identifier: "copyFilesActions", copyFiles: [copyFilesAction]).hash)
        }

        // Then
        XCTAssertEqual(results.count, 1)
    }

    func test_hash_returnsTheRightContent() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let filePath = temporaryDirectory.appending(component: "file")
        try await fileSystem.touch(filePath)
        let copyFilesAction = CopyFilesAction(
            name: "action",
            destination: .resources,
            subpath: "sub-directory",
            files: [
                CopyFileElement.file(
                    path: filePath,
                    condition: .when(Set([.macos])),
                    codeSignOnCopy: true
                ),
            ]
        )

        // When
        let got = try await subject.hash(identifier: "copyFilesActions", copyFiles: [copyFilesAction])

        // Then
        XCTAssertEqual(got, MerkleNode(
            hash: "bee08a6b2a62c3722cd4f95b4e6366e2",

            identifier: "copyFilesActions",
            children: [
                MerkleNode(
                    hash: "b2bae3352cca3429a35d6321df8faa83",
                    identifier: "action",
                    children: [
                        MerkleNode(
                            hash: "418c5509e2171d55b0aee5c2ea4442b5",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "55b558c7ef820e6e00e5993b9e55d93b",
                            identifier: "destination",
                            children: []
                        ),
                        MerkleNode(
                            hash: "a513dff02e1d54f35f36556fb1dd6e88",
                            identifier: "files",
                            children: [
                                MerkleNode(
                                    hash: "7178d66b2f9f58b50207c4ac3eef73d4",
                                    identifier: filePath.pathString,
                                    children: [
                                        MerkleNode(
                                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                                            identifier: "content",

                                            children: []
                                        ),
                                        MerkleNode(
                                            hash: "cfcd208495d565ef66e7dff9f98764da",
                                            identifier: "isReference",
                                            children: []
                                        ),
                                        MerkleNode(
                                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                                            identifier: "codeSignOnCopy",
                                            children: []
                                        ),
                                        MerkleNode(
                                            hash: "4ed91b7e02b960dc31256de17f3f131f",
                                            identifier: "condition",
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
                            ]
                        ),
                        MerkleNode(
                            hash: "d18d3d91d86b6429bf6cc4cf4ec5b99a",
                            identifier: "subpath",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }
}
