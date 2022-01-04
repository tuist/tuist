import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class TemplateLocationParserTests: TuistUnitTestCase {
    private var subject: TemplateLocationParser!

    override func setUp() {
        super.setUp()
        subject = TemplateLocationParser(system: system)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_parse_branch_name_for_given_url_template() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate@develop"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        XCTAssertNotNil(branch)
        XCTAssertEqual("develop", branch)
    }

    func test_parse_branch_name_for_given_ssh_url_template() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git@develop"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        XCTAssertNotNil(branch)
        XCTAssertEqual("develop", branch)
    }

    func test_nil_branch_when_not_branch_found_in_template_url() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        XCTAssertNil(branch)
    }

    func test_nil_branch_when_not_branch_found_in_template_ssh_url() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        XCTAssertNil(branch)
    }

    func test_parse_template_url_when_template_url_has_branch_name_on_it() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate@develop"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        XCTAssertEqual("https://github.com/tuist/ExampleTuistTemplate", repositoryURL)
    }

    func test_parse_template_url_when_template_ssh_url_has_branch_name_on_it() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git@develop"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        XCTAssertEqual("git@github.com:tuist/ExampleTuistTemplate.git", repositoryURL)
    }

    func test_parse_template_url_when_template_url_has_not_branch_name_on_it() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        XCTAssertEqual("https://github.com/tuist/ExampleTuistTemplate", repositoryURL)
    }

    func test_parse_template_url_when_template_ssh_url_has_not_branch_name_on_it() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        XCTAssertEqual("git@github.com:tuist/ExampleTuistTemplate.git", repositoryURL)
    }
}
