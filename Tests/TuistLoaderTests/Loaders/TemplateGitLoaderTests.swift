import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class TemplateGitLoaderTests: TuistUnitTestCase {
    var subject: TemplateGitLoader!
    var templateLoader: MockTemplateLoader!
    var gitHandler: MockGitHandler!

    override func setUp() {
        super.setUp()
        templateLoader = MockTemplateLoader()
        gitHandler = MockGitHandler()
        subject = TemplateGitLoader(
            templateLoader: templateLoader,
            fileHandler: FileHandler.shared,
            gitHandler: gitHandler,
            templateLocationParser: TemplateLocationParser()
        )
    }

    override func tearDown() {
        gitHandler = nil
        subject = nil
        templateLoader = nil
        super.tearDown()
    }

    func test_loadTemplatePath_isSameWithClonedRepository() throws {
        // Given
        var clonedRepositoryPath: AbsolutePath?
        gitHandler.cloneToStub = { _, path in
            clonedRepositoryPath = path
        }

        var pathToLoadTemplateFrom: AbsolutePath?
        templateLoader.loadTemplateStub = { path in
            pathToLoadTemplateFrom = path
            return TuistGraph.Template(
                description: ""
            )
        }

        // When
        try subject.loadTemplate(from: "https://url/to/repo.git", closure: { _ in })

        // Then
        XCTAssertNotNil(pathToLoadTemplateFrom)
        XCTAssertEqual(pathToLoadTemplateFrom, clonedRepositoryPath)
    }
}
