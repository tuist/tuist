import CryptoKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import Testing
@testable import TuistCacheEE

struct SignatureVerifierMiddlewareTests {
    private let base64SigningKey = "MC4CAQAwBQYDK2VwBCIEIBAkV1Ft1/cpL4xfyxG1ZKHSbgT5BXaGXikM4/NqIUAp"

    @Test func forwards_the_request_when_no_cache_path() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/test"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted)

        let (gotResponse, gotBody) = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            return (response, nil)
        }

        #expect(gotResponse == response)
    }

    @Test func forwards_the_request_when_cache_path_and_no_hash() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/cache"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted)

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            return (response, nil)
        }

        #expect(gotResponse == response)
    }

    @Test func throws_when_cache_path_and_hash_and_missing_header() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/cache?hash=123456"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted)

        await #expect(throws: SignatureVerifierMiddlewareError.self, performing: {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: operationID
            ) { _, _, _ in
                return (response, nil)
            }
        })
    }

    @Test func throws_when_cache_path_and_hash_and_invalid_signature_header() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/cache?hash=123456"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted, headerFields: [HTTPField.Name("x-tuist-signature")!: "invalid"])

        await #expect(throws: SignatureVerifierMiddlewareError.self, performing: {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: operationID
            ) { _, _, _ in
                return (response, nil)
            }
        })
    }

    @Test func doesnt_throw_when_cache_path_and_hash_and_invalid_signature_header() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/cache?hash=123456"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .badRequest, headerFields: [HTTPField.Name("x-tuist-signature")!: "invalid"])

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            return (response, nil)
        }

        #expect(gotResponse == response)
    }

    @Test func forwards_the_request_when_cache_path_and_hash_and_valid_signature_header() async throws {
        let subject = SignatureVerifierMiddleware(isDevelopment: false, base64SigningKey: base64SigningKey)
        let signature = try subject.signWithBase64SigningKey("123456")
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: nil,
            path: "/api/cache?hash=123456"
        )
        let baseURL = URL(string: "https://test.tuist.dev")!
        let operationID = UUID().uuidString
        let response = HTTPResponse(status: .accepted, headerFields: [HTTPField.Name("x-tuist-signature")!: signature])

        _ = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: operationID
        ) { _, _, _ in
            return (response, nil)
        }
    }
}
