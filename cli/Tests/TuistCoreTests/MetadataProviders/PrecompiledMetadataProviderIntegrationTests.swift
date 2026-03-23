import FileSystem
import FileSystemTesting
import Foundation
import Path
import TuistSupport
import Testing

@testable import TuistCore
@testable import TuistTesting

struct PrecompiledMetadataProviderIntegrationTests {
    let subject: PrecompiledMetadataProvider

    init() {
        subject = PrecompiledMetadataProvider()
    }

    @Test(.inTemporaryDirectory) func test_architectures() async throws {
        // Given
        let frameworkPath = try await temporaryFixture("xpm.framework")

        // When
        let got = try await subject.architectures(
            binaryPath: FrameworkMetadataProvider()
                .loadMetadata(at: frameworkPath, status: .required).binaryPath
        )

        // Then
        #expect(got.map(\.rawValue).sorted() == ["arm64", "x86_64"])
    }

    @Test(.inTemporaryDirectory) func test_uuids() async throws {
        // Given
        let frameworkPath = try await temporaryFixture("xpm.framework")

        // When
        let got = try await subject.uuids(
            binaryPath: FrameworkMetadataProvider()
                .loadMetadata(at: frameworkPath, status: .required).binaryPath
        )

        // Then
        let expected = Set([
            UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
            UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
        ])
        #expect(got == expected)
    }

    private func temporaryFixture(_ pathString: String) async throws -> AbsolutePath {
        let path = try RelativePath(validating: pathString)
        let fixturePath = SwiftTestingHelper.fixturePath(path: path)
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let destinationPath = temporaryPath.appending(component: path.basename)
        try await FileSystem().copy(fixturePath, to: destinationPath)
        return destinationPath
    }
}
