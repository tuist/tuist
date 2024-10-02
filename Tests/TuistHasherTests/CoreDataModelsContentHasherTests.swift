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

final class CoreDataModelsContentHasherTests: TuistUnitTestCase {
    private var subject: CoreDataModelsContentHasher!

    override func setUp() async throws {
        try await super.setUp()
        subject = CoreDataModelsContentHasher(contentHasher: ContentHasher())
    }

    override func tearDown() async throws {
        subject = nil
        try await super.tearDown()
    }

    func test_hash_isDeterministic() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let coreDataModelPath = temporaryDirectory.appending(component: "Test.xcdatamodeld")
        let v1 = coreDataModelPath.appending(component: "v1.xcdatamodel")
        let v2 = coreDataModelPath.appending(component: "v2.xcdatamodel")
        let xccurrentVersionPath = coreDataModelPath.appending(component: ".xccurrentversion")
        try await fileSystem.makeDirectory(at: v1)
        try await fileSystem.makeDirectory(at: v2)
        try await fileSystem.writeText(xccurrentVersionPath.basename, at: xccurrentVersionPath)
        try await fileSystem.writeText("contents", at: v1.appending(component: "contents"))
        try await fileSystem.writeText("contents", at: v2.appending(component: "contents"))
        let coreDataModels = [CoreDataModel(
            path: coreDataModelPath,
            versions: [v1, v2],
            currentVersion: "v1"
        )]
        var hashes: Set<String> = Set()

        // When
        for _ in 1 ... 100 {
            hashes.insert(try subject.hash(
                identifier: "coreDataModels",
                coreDataModels: coreDataModels,
                sourceRootPath: temporaryDirectory
            ).hash)
        }

        // Then
        XCTAssertEqual(hashes.count, 1)
    }

    func test_hash_returnsAValidTree() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let coreDataModelPath = temporaryDirectory.appending(component: "Test.xcdatamodeld")
        let v1 = coreDataModelPath.appending(component: "v1.xcdatamodel")
        let v2 = coreDataModelPath.appending(component: "v2.xcdatamodel")
        let xccurrentVersionPath = coreDataModelPath.appending(component: ".xccurrentversion")
        try await fileSystem.makeDirectory(at: v1)
        try await fileSystem.makeDirectory(at: v2)
        try await fileSystem.writeText(xccurrentVersionPath.basename, at: xccurrentVersionPath)
        try await fileSystem.writeText("contents", at: v1.appending(component: "contents"))
        try await fileSystem.writeText("contents", at: v2.appending(component: "contents"))
        let coreDataModels = [CoreDataModel(
            path: coreDataModelPath,
            versions: [v1, v2],
            currentVersion: "v1"
        )]

        // When
        let got = try subject.hash(
            identifier: "coreDataModels",
            coreDataModels: coreDataModels,
            sourceRootPath: temporaryDirectory
        )

        print(got)

        // Then
        XCTAssertEqual(got, MerkleNode(
            hash: "aca4c8d17d460a3213495d3e704827ed",
            identifier: "coreDataModels",
            children: [
                MerkleNode(
                    hash: "687ce1ef085fe7374f5f5a57a8583643",
                    identifier: coreDataModelPath.relative(to: temporaryDirectory).pathString,
                    children: [
                        MerkleNode(
                            hash: "9d54ac3c04cee9afeb00227788035726-98bf7d8c15784f0a3d63204441e1e2aa-98bf7d8c15784f0a3d63204441e1e2aa",
                            identifier: "content",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }
}
