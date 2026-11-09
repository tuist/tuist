import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import TuistHTTP

struct OutputWarningsMiddlewareTests {
    private let url = URL(string: "https://test.tuist.dev")!
    private let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test")

    @Test func intercept_returns_response_when_no_warnings_header() async throws {
        let subject = OutputWarningsMiddleware()
        let response = HTTPResponse(status: 200)

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test"
        ) { _, body, _ in
            (response, body)
        }

        #expect(gotResponse.status == response.status)
    }

    @Test func intercept_handles_empty_warnings_header_without_error() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = ""

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test"
        ) { _, body, _ in
            (response, body)
        }

        #expect(gotResponse.status == response.status)
    }

    @Test func intercept_handles_whitespace_warnings_header_without_error() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = "   \n\t  "

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test"
        ) { _, body, _ in
            (response, body)
        }

        #expect(gotResponse.status == response.status)
    }

    @Test func intercept_handles_empty_base64_data_without_error() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = Data().base64EncodedString()

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test"
        ) { _, body, _ in
            (response, body)
        }

        #expect(gotResponse.status == response.status)
    }

    @Test func intercept_throws_couldntConvertToData_when_invalid_base64() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = "!!!invalid-base64!!!"

        await #expect(throws: OutputWarningsMiddlewareError.couldntConvertToData) {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "test"
            ) { _, body, _ in
                (response, body)
            }
        }
    }

    @Test func intercept_throws_invalidSchema_when_not_string_array() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        let invalidJsonData = try JSONSerialization.data(withJSONObject: ["key": "value"])
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = invalidJsonData.base64EncodedString()

        await #expect(throws: OutputWarningsMiddlewareError.invalidSchema) {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "test"
            ) { _, body, _ in
                (response, body)
            }
        }
    }

    @Test func intercept_processes_valid_warnings_successfully() async throws {
        let subject = OutputWarningsMiddleware()
        var response = HTTPResponse(status: 200)
        let warnings = ["Warning 1: Deprecated option", "Warning 2: Please upgrade"]
        let validJsonData = try JSONSerialization.data(withJSONObject: warnings)
        response.headerFields[HTTPField.Name("x-tuist-warnings")!] = validJsonData.base64EncodedString()

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test"
        ) { _, body, _ in
            (response, body)
        }

        #expect(gotResponse.status == response.status)
    }
}
