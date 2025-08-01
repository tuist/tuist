import Foundation
import Mockable
import Path
import TuistCore
import TuistTesting
import XCTest

@testable import TuistHasher

final class XCConfigContentHasherTests: TuistUnitTestCase {
    private var subject: XCConfigContentHasher!
    private var contentHasher: MockContentHashing!

    private var sourceFile1Path: AbsolutePath!
    private var sourceFile2Path: AbsolutePath!

    override func setUp() async throws {
        try await super.setUp()
        contentHasher = .init()
        subject = XCConfigContentHasher(contentHasher: contentHasher)

        let temporaryDir = try temporaryPath()
        sourceFile1Path = temporaryDir.appending(component: "xcconfigFile1")
        sourceFile2Path = temporaryDir.appending(component: "xcconfigFile2")

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    override func tearDown() {
        sourceFile1Path = nil
        sourceFile2Path = nil
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_when_xcconfigHasNoIncludes() async throws {
        // Given
        try await fileSystem.writeText("xcconfigFile1", at: sourceFile1Path)

        // When
        let hash = try await subject.hash(path: sourceFile1Path)

        // Then
        XCTAssertEqual(
            hash,
            "xcconfigFile1-hash"
        )
    }

    func test_hash_when_xcconfigHasRelativeInclude() async throws {
        // Given
        try await fileSystem.writeText(
            """
            #include "xcconfigFile2"
            xcconfigFile1
            """,
            at: sourceFile1Path
        )
        try await fileSystem.writeText("xcconfigFile2", at: sourceFile2Path)

        // When
        let hash = try await subject.hash(path: sourceFile1Path)

        // Then
        XCTAssertEqual(
            hash,
            """
            #include "xcconfigFile2"
            xcconfigFile1-hashxcconfigFile2-hash
            """
        )
    }

    func test_hash_when_xcconfigHasAbsoluteInclude() async throws {
        // Given
        try await fileSystem.writeText(
            """
            #include "\(sourceFile2Path.pathString)"
            xcconfigFile1
            """,
            at: sourceFile1Path
        )
        try await fileSystem.writeText("xcconfigFile2", at: sourceFile2Path)

        // When
        let hash = try await subject.hash(path: sourceFile1Path)

        // Then
        XCTAssertEqual(
            hash,
            """
            #include "\(sourceFile2Path.pathString)"
            xcconfigFile1-hashxcconfigFile2-hash
            """
        )
    }
}
