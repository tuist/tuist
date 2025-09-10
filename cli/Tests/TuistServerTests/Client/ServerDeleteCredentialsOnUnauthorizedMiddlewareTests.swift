import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
@testable import TuistServer

struct ServerDeleteCredentialsOnUnauthorizedMiddlewareTests {
    struct TestError: Error, Equatable {}

    private let subject: ServerDeleteCredentialsOnUnauthorizedMiddleware
    private let serverAuthenticationController = MockServerAuthenticationControlling()

    init() {
        subject = ServerDeleteCredentialsOnUnauthorizedMiddleware(serverAuthenticationController: serverAuthenticationController)
    }

    @Test func deletesCredentials_when_unauthorizedResponse() async throws {
        let request = HTTPRequest(method: .get, scheme: "https", authority: nil, path: "/api")
        let baseURL = URL(string: "https://tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .unauthorized)
        given(serverAuthenticationController).deleteCredentials(serverURL: .value(baseURL)).willReturn()

        let (middlewareResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, body, _ in
            return (response, body)
        }

        #expect(middlewareResponse == response)
    }

    @Test func bubbleCredentialDeletionErrors_when_unAuthorizedResponse_and_deletionFails() async throws {
        let request = HTTPRequest(method: .get, scheme: "https", authority: nil, path: "/api")
        let baseURL = URL(string: "https://tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .unauthorized)
        let error = TestError()
        given(serverAuthenticationController).deleteCredentials(serverURL: .value(baseURL)).willThrow(error)

        await #expect(throws: error, performing: {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: operationID
            ) { _, body, _ in
                return (response, body)
            }
        })
    }

    @Test func doesntDeleteCredentials_when_unAuthorizedResponse() async throws {
        let request = HTTPRequest(method: .get, scheme: "https", authority: nil, path: "/api")
        let baseURL = URL(string: "https://tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted)

        let (middlewareResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, body, _ in
            return (response, body)
        }

        verify(serverAuthenticationController).deleteCredentials(serverURL: .value(baseURL)).called(0)
        #expect(middlewareResponse == response)
    }
}
