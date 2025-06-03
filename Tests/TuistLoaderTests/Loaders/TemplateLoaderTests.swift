import Mockable
import Path
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

final class TemplateLoaderTests: TuistUnitTestCase {
    private var subject: TemplateLoader!
    private var manifestLoader: MockManifestLoading!
    private var rootDirectoryLocator: MockRootDirectoryLocating!

    override func setUp() {
        super.setUp()
        manifestLoader = .init()
        rootDirectoryLocator = .init()
        subject = TemplateLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    override func tearDown() {
        manifestLoader = nil
        rootDirectoryLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_loadTemplate_when_not_found() async throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        await XCTAssertThrowsSpecific(
            { try await self.subject.loadTemplate(at: temporaryPath, plugins: .none) },
            ManifestLoaderError.manifestNotFound(temporaryPath)
        )
    }

    func test_loadTemplate_files() async throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        XCTAssertEqual(got, TuistCore.Template(
            description: "desc",
            items: [Template.Item(
                path: try RelativePath(validating: "generateOne"),
                contents: .file(temporaryPath.appending(component: "fileOne"))
            )]
        ))
    }
}
