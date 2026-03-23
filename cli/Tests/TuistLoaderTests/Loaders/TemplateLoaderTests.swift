import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

struct TemplateLoaderTests {
    private let subject: TemplateLoader
    private let manifestLoader: MockManifestLoading
    private let rootDirectoryLocator: MockRootDirectoryLocating

    init() {
        manifestLoader = .init()
        rootDirectoryLocator = .init()
        subject = TemplateLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    @Test(.inTemporaryDirectory) func loadTemplate_when_not_found() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(manifestLoader)
            .loadTemplate(at: .any)
            .willProduce { path in
                throw ManifestLoaderError.manifestNotFound(path)
            }
        given(manifestLoader)
            .register(plugins: .any)
            .willReturn(())

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryPath)

        // Then
        await #expect(throws: ManifestLoaderError.manifestNotFound(temporaryPath)) {
            try await self.subject.loadTemplate(at: temporaryPath, plugins: .none)
        }
    }

    @Test(.inTemporaryDirectory) func loadTemplate_files() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(manifestLoader)
            .loadTemplate(at: .any)
            .willReturn(
                ProjectDescription.Template(
                    description: "desc",
                    items: [ProjectDescription.Template.Item(
                        path: "generateOne",
                        contents: .file("fileOne")
                    )]
                )
            )

        given(manifestLoader)
            .register(plugins: .any)
            .willReturn(())

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryPath)

        // When
        let got = try await subject.loadTemplate(at: temporaryPath, plugins: .none)

        // Then
        #expect(got == TuistCore.Template(
            description: "desc",
            items: [Template.Item(
                path: try RelativePath(validating: "generateOne"),
                contents: .file(temporaryPath.appending(component: "fileOne"))
            )]
        ))
    }
}
