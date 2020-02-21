import Foundation
import TuistSupportTesting
import XCTest
@testable import TuistEnvKit

final class GitHubClientErrorTests: XCTestCase {
    func test_errorDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertEqual(GitHubClientError.sessionError(error).description, "Session error: \(error.localizedDescription)")
        XCTAssertEqual(GitHubClientError.missingData.description, "No data received from the GitHub API")
        XCTAssertEqual(GitHubClientError.decodingError(error).description, "Error decoding JSON from API: \(error.localizedDescription)")
        XCTAssertEqual(GitHubClientError.invalidResponse.description, "Received an invalid response from the GitHub API")
    }
}

final class GitHubClientTests: XCTestCase {
    var subject: GitHubClient!
    var sessionScheduler: MockURLSessionScheduler!

    override func setUp() {
        super.setUp()
        sessionScheduler = MockURLSessionScheduler()
        subject = GitHubClient(sessionScheduler: sessionScheduler)
    }

    func test_execute_when_returns_an_error() throws {
        let request = URLRequest(url: URL(string: "http://test")!)
        sessionScheduler.stub(request: request, error: URLError(.badServerResponse))

        XCTAssertThrowsError(try subject.execute(request: request))
    }

    func test_execute_when_returns_no_data() {
        let request = URLRequest(url: URL(string: "http://test")!)

        XCTAssertThrowsError(try subject.execute(request: request))
    }

    func test_execute_when_returns_data_without_errors() throws {
        let request = URLRequest(url: URL(string: "http://test")!)
        let json: [String: Any] = ["test": "test"]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        sessionScheduler.stub(request: request, data: data)

        let gotData = try subject.execute(request: request)
        let got = try JSONSerialization.jsonObject(with: gotData, options: []) as? [String: String]
        XCTAssertEqual(got?["test"], "test")
    }
}
