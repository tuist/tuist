import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class URLSessionSchedulerErrorTests: TuistUnitTestCase {
    func test_type_when_noData() {
        // Given
        let request = URLRequest(url: URL.test())

        // When
        let got = URLSessionSchedulerError.noData(request).type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_noData() {
        // Given
        let request = URLRequest(url: URL.test())

        // When
        let got = URLSessionSchedulerError.noData(request).description

        // Then
        XCTAssertEqual(got, "An HTTP request to \(request.url!.absoluteString) returned no data")
    }
}
