import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class GitHubClientTests: TuistUnitTestCase {
    var subject: GitHubClient!
    var requestDisptacher: MockHTTPRequestDispatcher!
    var gitEnvironment: MockGitEnvironment!

    override func setUp() {
        super.setUp()
        requestDisptacher = MockHTTPRequestDispatcher()
        gitEnvironment = MockGitEnvironment()
        subject = GitHubClient(
            requestDispatcher: requestDisptacher,
            gitEnvironment: gitEnvironment
        )
    }

    override func tearDown() {
        requestDisptacher = nil
        gitEnvironment = nil
        subject = nil
        super.tearDown()
    }

    func test_deferred_includes_the_token_in_the_request() throws {
        // Given
        gitEnvironment.stubbedGithubAuthenticationResult = .success(.token("TOKEN"))

        // When
        let expectation = XCTestExpectation(description: "GitHubClient deferred when token")
        _ = subject.deferred(resource: HTTPResource<Void, Never>.noop())
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { _ in }
            )
        wait(for: [expectation], timeout: 10.0)

        // Then
        let request = try XCTUnwrap(requestDisptacher.requests.first)
        let headers = try XCTUnwrap(request.allHTTPHeaderFields)
        XCTAssertEqual(headers["Authorization"], "token TOKEN")
        XCTAssertEqual(headers["Accept"], "application/vnd.github.v3+json")
    }

    func test_deferred_includes_the_username_and_password_in_the_request() throws {
        // Given
        gitEnvironment.stubbedGithubAuthenticationResult = .success(
            .credentials(.init(username: "username", password: "password"))
        )

        // When
        let expectation = XCTestExpectation(description: "GitHubClient deferred when token")
        _ = subject.deferred(resource: HTTPResource<Void, Never>.noop())
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { _ in }
            )
        wait(for: [expectation], timeout: 10.0)

        // Then
        let request = try XCTUnwrap(requestDisptacher.requests.first)
        let headers = try XCTUnwrap(request.allHTTPHeaderFields)
        let data = "username:password".data(using: String.Encoding.utf8)!
        let encodedString = data.base64EncodedString()
        XCTAssertEqual(headers["Authorization"], "Basic \(encodedString)")
        XCTAssertEqual(headers["Accept"], "application/vnd.github.v3+json")
    }

    func test_deferred_when_no_authentication_is_available() throws {
        // Given
        gitEnvironment.stubbedGithubAuthenticationResult = .success(nil)

        // When
        let expectation = XCTestExpectation(description: "GitHubClient deferred when token")
        _ = subject.deferred(resource: HTTPResource<Void, Never>.noop())
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { _ in }
            )
        wait(for: [expectation], timeout: 10.0)

        // Then
        let request = try XCTUnwrap(requestDisptacher.requests.first)
        let headers = try XCTUnwrap(request.allHTTPHeaderFields)
        XCTAssertNil(headers["Authorization"])
        XCTAssertEqual(headers["Accept"], "application/vnd.github.v3+json")
    }
    
    func test_something() throws {
        let expectation = XCTestExpectation(description: "GitHubClient deferred when token")
        var release: GitHubRelease?
        let client = GitHubClient()
        _ = client.deferred(resource: GitHubRelease.latest(repositoryFullName: "tuist/tuist"))
            .sink { error in
                print(error)
                expectation.fulfill()
            } receiveValue: { (response) in
                print(response)
                release = response.object
            }
        wait(for: [expectation], timeout: 10.0)


    }
}
