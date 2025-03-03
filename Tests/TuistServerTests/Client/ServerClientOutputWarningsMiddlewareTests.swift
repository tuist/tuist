import Foundation
import HTTPTypes
import OpenAPIRuntime
import ServiceContextModule
import TuistSupport
import XCTest

@testable import TuistServer
@testable import TuistSupportTesting

private final class MockWarningController: WarningControlling {
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
        try await ServiceContext.withTestingDependencies {
            // Given
            let url = URL(string: "https://test.tuist.io")!
            let warnings = ["foo", "bar"]
            let base64edJsonWarnings = (try JSONSerialization.data(withJSONObject: warnings)).base64EncodedString()
            let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
            let response = HTTPResponse(
                status: 200,
                headerFields: [
                    try XCTUnwrap(HTTPField.Name("x-tuist-cloud-warnings")): base64edJsonWarnings,
                ]
            )

            // When
            let (gotResponse, _) = try await subject
                .intercept(request, body: nil, baseURL: url, operationID: "123") { _, _, _ in
                    (response, nil)
                }

            // Then
            XCTAssertEqual(gotResponse, response)
            for warning in warnings {
                XCTAssertStandardOutput(pattern: warning)
            }
        }
    }

    func test_doesntOutputAnyWarning_whenTheHeaderIsAbsent() async throws {
        // Given
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)

        // When
        let (gotResponse, _) = try await subject
            .intercept(request, body: nil, baseURL: url, operationID: "123") { _, _, _ in
                (response, nil)
            }

        // Then
        XCTAssertEqual(gotResponse, response)
        let standardOutput = ServiceContext.current?.testingLogHandler?.collected[.warning, <=] ?? ""
        XCTAssertEqual(standardOutput, "")
    }
}
