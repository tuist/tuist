import Mockable
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistGit
import TuistSupport
import TuistTesting

@testable import TuistLoader

struct TemplateGitLoaderTests {
    private let subject: TemplateGitLoader
    private let templateLoader: MockTemplateLoading
    private let gitController: MockGitControlling

    init() {
        templateLoader = MockTemplateLoading()
        gitController = MockGitControlling()
        subject = TemplateGitLoader(
            templateLoader: templateLoader,
            fileHandler: FileHandler.shared,
            gitController: gitController,
            templateLocationParser: TemplateLocationParser()
        )
    }

    @Test func loadTemplatePath_isSameWithClonedRepository() async throws {
        // Given
        given(gitController)
            .clone(url: .any, to: .any)
            .willReturn()

        var pathToLoadTemplateFrom: AbsolutePath?
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willProduce { path, _ in
                pathToLoadTemplateFrom = path
                return TuistCore.Template(
                    description: ""
                )
            }

        // When
        try await subject.loadTemplate(from: "https://url/to/repo.git", closure: { _ in })

        // Then
        verify(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .called(1)
        verify(gitController)
            .clone(
                url: .any,
                to: .value(pathToLoadTemplateFrom)
            )
            .called(1)
    }
}
