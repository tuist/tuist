import Foundation
import OpenAPIRuntime
import TuistSupport
import XCTest
@testable import TuistServer
@testable import TuistSupportTesting

private class MockWarningController: WarningControlling {
    var warnings: [String] = []
    func append(warning: String) {
        warnings.append(warning)
    }

    func flush() {
        warnings.removeAll()
    }
}

final class ServerClientOutputWarningsMiddlewareTests: TuistUnitTestCase {
    fileprivate var warningController: MockWarningController!
    var subject: ServerClientOutputWarningsMiddleware!

    override func setUp() {
        super.setUp()
        warningController = MockWarningController()
        subject = ServerClientOutputWarningsMiddleware(warningController: warningController)
    }

    override func tearDown() {
        warningController = nil
        subject = nil
        super.tearDown()
    }

    func test_outputsWarnings_whenTheHeaderIsPresent() async throws {
        // Given
        let url = URL(string: "https://test.tuist.io")!
        let warnings = ["foo", "bar"]
        let base64edJsonWarnings = (try JSONSerialization.data(withJSONObject: warnings)).base64EncodedString()
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200,
            headerFields: [.init(name: "x-tuist-cloud-warnings", value: base64edJsonWarnings)]
        )

        // When
        let gotResponse = try await subject.intercept(request, baseURL: url, operationID: "123") { _, _ in
            response
        }

        // Then
        XCTAssertEqual(gotResponse, response)
        for warning in warnings {
            XCTAssertStandardOutput(pattern: warning)
        }
    }

    func test_doesntOutputAnyWarning_whenTheHeaderIsAbsent() async throws {
        // Given
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(statusCode: 200)

        // When
        let gotResponse = try await subject.intercept(request, baseURL: url, operationID: "123") { _, _ in
            response
        }

        // Then
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(TestingLogHandler.collected[.warning, <=], "")
    }
}
