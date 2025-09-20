import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
@testable import TuistHasher

struct XCConfigContentHasherTests {
    private var subject: XCConfigContentHasher!
    private var contentHasher: MockContentHashing!

    private let fileSystem = FileSystem()

    private var sourceFile1Path: AbsolutePath!
    private var sourceFile2Path: AbsolutePath!
    private var sourceFile3Path: AbsolutePath!

    init() throws {
        contentHasher = .init()
        subject = XCConfigContentHasher(contentHasher: contentHasher)

        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        sourceFile1Path = temporaryDirectory.appending(component: "xcconfigFile1.xcconfig")
        sourceFile2Path = temporaryDirectory.appending(component: "xcconfigFile2.xcconfig")
        sourceFile3Path = temporaryDirectory.appending(component: "xcconfigFile3.xcconfig")

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    // MARK: - Tests

    @Test(.inTemporaryDirectory)
    func hashWhenXCConfigHasNoIncludes() async throws {
        // Given
        try await fileSystem.writeText("xcconfigFile1", at: sourceFile1Path)

        // When
        let hash = try await subject.hash(path: sourceFile1Path)

        // Then
        #expect(hash == "xcconfigFile1-hash")
    }

    @Test(.inTemporaryDirectory)
    func hashWhenXCConfigHasRelativeInclude() async throws {
        // Given
        try await fileSystem.writeText(
            """
            #include "xcconfigFile2.xcconfig"
            xcconfigFile1
            """,
            at: sourceFile1Path
        )
        try await fileSystem.writeText("xcconfigFile2", at: sourceFile2Path)

        // When
        let hash = try await subject.hash(path: sourceFile1Path)

        // Then
        #expect(
            hash ==
                """
                #include "xcconfigFile2.xcconfig"
                xcconfigFile1-hashxcconfigFile2-hash
                """
        )
    }

    @Test(.inTemporaryDirectory)
    func hashWhenXCConfigHasAbsoluteInclude() async throws {
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
        #expect(
            hash ==
                """
                #include "\(sourceFile2Path.pathString)"
                xcconfigFile1-hashxcconfigFile2-hash
                """
        )
    }

    @Test(.inTemporaryDirectory)
    func throwErrorAtRecursiveInclude() async throws {
        // Given
        try await fileSystem.writeText(
            """
            #include "xcconfigFile2.xcconfig"
            xcconfigFile1
            """,
            at: sourceFile1Path
        )
        try await fileSystem.writeText(
            """
            #include "xcconfigFile3.xcconfig"
            xcconfigFile2
            """,
            at: sourceFile2Path
        )
        try await fileSystem.writeText(
            """
            #include "xcconfigFile1.xcconfig"
            xcconfigFile3
            """,
            at: sourceFile3Path
        )

        // Then
        await #expect(
            throws: XCConfigContentHasherError.recursiveIncludeInXCConfigDetected(
                path: sourceFile1Path,
                includedPaths: [sourceFile1Path, sourceFile2Path, sourceFile3Path, sourceFile1Path]
            ),
            performing: {
                try await subject.hash(path: sourceFile1Path)
            }
        )
    }
}
