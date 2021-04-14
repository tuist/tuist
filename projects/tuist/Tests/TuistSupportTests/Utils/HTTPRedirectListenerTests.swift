import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class HTTPRedirectListenerErrorTests: XCTestCase {
    func test_type_when_httpServer() {
        // Given
        let error = TestError("error")
        let subject = HTTPRedirectListenerError.httpServer(error)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_httpServer() {
        // Given
        let error = TestError("error")
        let subject = HTTPRedirectListenerError.httpServer(error)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The redirect HTTP server faild to start with the following error: \(error).")
    }
}
