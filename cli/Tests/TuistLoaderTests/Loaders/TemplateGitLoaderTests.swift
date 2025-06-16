import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistGit
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistLoader

final class TemplateGitLoaderTests: TuistUnitTestCase {
    private var subject: TemplateGitLoader!
    private var templateLoader: MockTemplateLoading!
    private var gitController: MockGitControlling!

    override func setUp() {
        super.setUp()
        templateLoader = MockTemplateLoading()
        gitController = MockGitControlling()
        subject = TemplateGitLoader(
            templateLoader: templateLoader,
            fileHandler: FileHandler.shared,
            gitController: gitController,
            templateLocationParser: TemplateLocationParser()
        )
    }

    override func tearDown() {
        gitController = nil
        subject = nil
        templateLoader = nil
        super.tearDown()
    }

    func test_loadTemplatePath_isSameWithClonedRepository() async throws {
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
