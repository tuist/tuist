import Foundation
import TuistSupport
import XCTest

@testable import TuistEnvKit
@testable import TuistSupportTesting

final class HTTPClientErrorTests: XCTestCase {
    func test_type() {
        // Given
        let error = NSError.test()
        let url = URL.test()

        // Then
        XCTAssertEqual(HTTPClientError.clientError(url, error).type, .abort)
        XCTAssertEqual(HTTPClientError.noData(url).type, .abort)
    }

    func test_description() {
        // Given
        let error = NSError.test()
        let url = URL.test()

        // Then
        XCTAssertEqual(
            HTTPClientError.clientError(url, error).description,
            "The request to \(url.absoluteString) errored with: \(error.localizedDescription)"
        )
        XCTAssertEqual(HTTPClientError.noData(url).description, "The request to \(url.absoluteString) returned no data")
    }
}
