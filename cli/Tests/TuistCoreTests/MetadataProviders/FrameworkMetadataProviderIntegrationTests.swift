import FileSystem
import FileSystemTesting
import Foundation
import Path
import TuistSupport
import Testing

@testable import TuistCore
@testable import TuistTesting

struct FrameworkMetadataProviderIntegrationTests {
    let subject: FrameworkMetadataProvider
    let fileSystem: FileSysteming

    init() {
        subject = FrameworkMetadataProvider()
        fileSystem = FileSystem()
    }

    @Test(.inTemporaryDirectory) func test_bcsymbolmapPaths() async throws {
        // Given
        let testPath = try await temporaryFixture("PrebuiltFramework/")
        let frameworkPath = try await fileSystem.glob(directory: testPath, include: ["*.framework"]).collect().first!

        // When
        let got = try await subject.bcsymbolmapPaths(frameworkPath: frameworkPath).sorted()

        // Then
        #expect(got == [
            testPath.appending(component: "2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap"),
            testPath.appending(component: "773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap"),
        ])
    }

    @Test(.inTemporaryDirectory) func test_dsymPath() async throws {
        // Given
        let testPath = try await temporaryFixture("PrebuiltFramework/")
        let frameworkPath = try await fileSystem.glob(directory: testPath, include: ["*.framework"]).collect().first!

        // When
        let got = try await subject.dsymPath(frameworkPath: frameworkPath)

        // Then
        #expect(got == testPath.appending(component: "\(frameworkPath.basename).dSYM"))
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
