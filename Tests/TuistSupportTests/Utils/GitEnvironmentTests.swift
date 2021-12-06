import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class GitEnvironmentErrorTests: TuistUnitTestCase {
    func test_type_when_githubCredentialsFillError() {
        XCTAssertEqual(GitEnvironmentError.githubCredentialsFillError("test").type, .bug)
    }

    func test_description_when_githubCredentialsFillError() {
        XCTAssertEqual(
            GitEnvironmentError.githubCredentialsFillError("test").description,
            "Trying to get your environment's credentials for https://github.com failed with the following error: test"
        )
    }
}

final class GitEnvironmentTests: TuistUnitTestCase {
    var subject: GitEnvironment!
    var envVariables: [String: String]! = [:]

    override func setUp() {
        super.setUp()
        subject = GitEnvironment(environment: { self.envVariables })
    }

    override func tearDown() {
        subject = nil
        envVariables = nil
        super.tearDown()
    }

    func test_githubAuthentication_returns_the_environment_variable_when_the_token_is_present() throws {
        // Given
        let expectation = XCTestExpectation(description: "Git authentication")
        envVariables[Constants.EnvironmentVariables.githubAPIToken] = "TOKEN"

        // When
        _ = subject.githubAuthentication()
            .sink { _ in
            } receiveValue: { value in
                XCTAssertEqual(value, .token("TOKEN"))
                expectation.fulfill()
            }
        wait(for: [expectation], timeout: 10.0)
    }

    func test_githubAuthentication_returns_the_system_credentials_when_the_token_is_not_present() throws {
        // Given
        let expectation = XCTestExpectation(description: "Git authentication")
        let output = """
        username=tuist
        password=rocks
        """
        system.succeedCommand(["/usr/bin/env", "echo", "url=https://github.com"], output: output)
        system.succeedCommand(["/usr/bin/env", "git", "credential", "fill"], output: output)

        // When
        _ = subject.githubAuthentication()
            .sink { _ in
            } receiveValue: { value in
                XCTAssertEqual(value, .credentials(.init(username: "tuist", password: "rocks")))
                expectation.fulfill()
            }
        wait(for: [expectation], timeout: 10.0)
    }

    func test_githubCredentials_when_the_command_fails() throws {
        // Given
        system.errorCommand(["/usr/bin/env", "echo", "url=https://github.com"])
        system.errorCommand(["/usr/bin/env", "git", "credential", "fill"])
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
        system.succeedCommand(["/usr/bin/env", "echo", "url=https://github.com"], output: output)
        system.succeedCommand(["/usr/bin/env", "git", "credential", "fill"], output: output)
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
        system.succeedCommand(["/usr/bin/env", "echo", "url=https://github.com"], output: output)
        system.succeedCommand(["/usr/bin/env", "git", "credential", "fill"], output: output)
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
