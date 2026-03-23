import Foundation
import Testing

@testable import TuistSupport
@testable import TuistTesting

struct TemplateLocationParserTests {
    private let subject: TemplateLocationParser
    init() {
        subject = TemplateLocationParser(system: system)
    }


    @Test
    func test_parse_branch_name_for_given_url_template() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate@develop"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        #expect(branch != nil)
        #expect("develop" == branch)
    }

    @Test
    func test_parse_branch_name_for_given_ssh_url_template() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git@develop"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        #expect(branch != nil)
        #expect("develop" == branch)
    }

    @Test
    func test_nil_branch_when_not_branch_found_in_template_url() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        #expect(branch == nil)
    }

    @Test
    func test_nil_branch_when_not_branch_found_in_template_ssh_url() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git"

        // When
        let branch = subject.parseRepositoryBranch(from: urlTemplate)

        // Then
        #expect(branch == nil)
    }

    @Test
    func test_parse_template_url_when_template_url_has_branch_name_on_it() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate@develop"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        #expect("https://github.com/tuist/ExampleTuistTemplate" == repositoryURL)
    }

    @Test
    func test_parse_template_url_when_template_ssh_url_has_branch_name_on_it() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git@develop"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        #expect("git@github.com:tuist/ExampleTuistTemplate.git" == repositoryURL)
    }

    @Test
    func test_parse_template_url_when_template_url_has_not_branch_name_on_it() {
        // Given
        let urlTemplate = "https://github.com/tuist/ExampleTuistTemplate"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        #expect("https://github.com/tuist/ExampleTuistTemplate" == repositoryURL)
    }

    @Test
    func test_parse_template_url_when_template_ssh_url_has_not_branch_name_on_it() {
        // Given
        let urlTemplate = "git@github.com:tuist/ExampleTuistTemplate.git"

        // When
        let repositoryURL = subject.parseRepositoryURL(from: urlTemplate)

        // Then
        #expect("git@github.com:tuist/ExampleTuistTemplate.git" == repositoryURL)
    }
}
