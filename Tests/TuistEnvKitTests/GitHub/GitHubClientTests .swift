import Foundation
@testable import TuistEnvKit
import XCTest

final class GitHubClientErrorTests: XCTestCase {
    func test_errorDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertEqual(GitHubClientError.sessionError(error).description, "Session error: \(error.localizedDescription).")
        XCTAssertEqual(GitHubClientError.missingData.description, "No data received from the GitHub API.")
        XCTAssertEqual(GitHubClientError.decodingError(error).description, "Error decoding JSON from API: \(error.localizedDescription)")
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
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        let request = URLRequest(url: URL(string: "http://test")!)
        sessionScheduler.scheduleStub = { _request in
            if _request == request {
                return (error, nil)
            } else {
                return (nil, nil)
            }
        }
        XCTAssertThrowsError(try subject.execute(request: request))
    }

    func test_execute_when_returns_no_data() {
        let request = URLRequest(url: URL(string: "http://test")!)
        sessionScheduler.scheduleStub = { _ in (nil, nil) }
        XCTAssertThrowsError(try subject.execute(request: request))
    }

    func test_execute_when_returns_data_without_errors() throws {
        let request = URLRequest(url: URL(string: "http://test")!)
        sessionScheduler.scheduleStub = { _request in
            if _request == request {
                let json: [String: Any] = ["test": "test"]
                let data = try! JSONSerialization.data(withJSONObject: json, options: [])
                return (nil, data)
            } else {
                return (nil, nil)
            }
        }
        let got = try subject.execute(request: request) as? [String: String]
        XCTAssertEqual(got?["test"], "test")
    }
}
