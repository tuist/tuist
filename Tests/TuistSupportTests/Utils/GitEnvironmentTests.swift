import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class GitEnvironmentErrorTests: TuistUnitTestCase {
    func test_type_when_githubCredentialsFillError() {
        XCTAssertEqual(GitEnvironmentError.githubCredentialsFillError("test").type, .bug)
    }

    func test_description_when_githubCredentialsFillError() {
        XCTAssertEqual(GitEnvironmentError.githubCredentialsFillError("test").description, "Trying to get your environment's credentials for https://github.com failed with the following error: test")
    }
}

final class GitEnvironmentTests: TuistUnitTestCase {
    var subject: GitEnvironment!

    override func setUp() {
        subject = GitEnvironment()
        super.setUp()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_githubCredentials_when_the_command_fails() throws {
        // Given
        system.errorCommand(["echo", "url=https://github.com"])
        system.errorCommand(["git", "credentials", "fill"])
        let expectation = XCTestExpectation(description: "Git credentials fill command")

        // When
        _ = subject.githubCredentials()
            .sink { completion in
                switch completion {
                case .failure:
                    expectation.fulfill()
                case .finished:
                    XCTFail("Expected to receive an error but it did not.")
                    expectation.fulfill()
                }
            } receiveValue: { _ in }
        wait(for: [expectation], timeout: 10.0)
    }

    func test_githubCredentials_when_the_command_returns_the_expected_output() throws {
        // Given
        let output = """
        username=tuist
        password=rocks
        """
        system.succeedCommand(["echo", "url=https://github.com"], output: output)
        system.succeedCommand(["git", "credentials", "fill"], output: output)
        let expectation = XCTestExpectation(description: "Git credentials fill command")

        // When
        _ = subject.githubCredentials()
            .sink { completion in
                switch completion {
                case .failure:
                    XCTFail("Expected to succeed but it failed")
                    expectation.fulfill()
                case .finished:
                    expectation.fulfill()
                }
            } receiveValue: { value in
                XCTAssertEqual(value?.username, "tuist")
                XCTAssertEqual(value?.password, "rocks")
            }
        wait(for: [expectation], timeout: 10.0)
    }

    func test_githubCredentials_when_the_commands_output_lacks_username_or_password() throws {
        // Given
        let output = """
        password=rocks
        """
        system.succeedCommand(["echo", "url=https://github.com"], output: output)
        system.succeedCommand(["git", "credentials", "fill"], output: output)
        let expectation = XCTestExpectation(description: "Git credentials fill command")

        // When
        _ = subject.githubCredentials()
            .sink { completion in
                switch completion {
                case .failure:
                    XCTFail("Expected to succeed but it failed")
                    expectation.fulfill()
                case .finished:
                    expectation.fulfill()
                }
            } receiveValue: { value in
                XCTAssertNil(value)
            }
        wait(for: [expectation], timeout: 10.0)
    }
}
