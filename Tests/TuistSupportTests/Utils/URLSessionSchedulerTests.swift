import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class URLSessionSchedulerErrorTests: TuistUnitTestCase {
    func test_type_when_noData() {
        // Given
        let url = URL.test()
        let request = URLRequest(url: url)
        let status = HTTPStatusCode.notFound
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: [:])!

        // When
        let got = URLSessionSchedulerError.httpError(status: status, response: response, request: request).type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_noData() {
        // Given
        let url = URL.test()
        let request = URLRequest(url: url)
        let status = HTTPStatusCode.notFound
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: [:])!

        // When
        let got = URLSessionSchedulerError.httpError(status: status, response: response, request: request).description

        // Then
        XCTAssertEqual(got, "We got an error \(status) from the request \(response.url!) \(request.httpMethod!)")
    }
}
