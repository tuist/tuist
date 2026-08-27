import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import TuistCache

/// The regional cache serves hot reads from a path that writes its own HTTP responses
/// instead of going through the handlers the OpenAPI document is exported from. Those
/// bytes are asserted here against the generated decoder, because the decoder checks the
/// content type before it decodes the status: a mismatch is rejected as a transport
/// error, which makes the typed case unreachable on that path even though the status is
/// right.
struct AcceleratedResponseDecodingTests {
    private struct StubTransport: ClientTransport {
        let response: HTTPResponse
        let body: HTTPBody?

        func send(
            _: HTTPRequest,
            body _: HTTPBody?,
            baseURL _: URL,
            operationID _: String
        ) async throws -> (HTTPResponse, HTTPBody?) {
            (response, body)
        }
    }

    private static let shedMessage =
        "The server is limiting concurrent artifact response streams; retry shortly"

    private func client(contentType: String) -> Client {
        let response = HTTPResponse(
            status: .tooManyRequests,
            headerFields: [
                .contentType: contentType,
                .retryAfter: "3",
            ]
        )
        let body = HTTPBody(#"{"message":"\#(Self.shedMessage)"}"#)
        return Client(
            serverURL: URL(string: "https://cache.tuist.dev")!,
            transport: StubTransport(response: response, body: body)
        )
    }

    private func download(with client: Client) async throws -> Operations.downloadModuleCacheArtifact.Output {
        try await client.downloadModuleCacheArtifact(
            .init(
                path: .init(id: "hash"),
                query: .init(
                    account_handle: "acme",
                    project_handle: "ios",
                    hash: "hash",
                    name: "target.zip"
                )
            )
        )
    }

    @Test func decodes_the_accelerated_shed_as_backpressure() async throws {
        // When
        let got = try await download(with: client(contentType: "application/json"))

        // Then
        guard case let .tooManyRequests(payload) = got else {
            Issue.record("expected a backpressure response, got \(got)")
            return
        }
        #expect(payload.headers.retry_hyphen_after == "3")
        switch payload.body {
        case let .json(error):
            #expect(error.message == Self.shedMessage)
        }
    }

    @Test func rejects_a_shed_whose_content_type_does_not_match_the_document() async throws {
        // The accelerated path used to answer `text/plain` here. The status was already
        // 429, so this reads as a passing contract until a client tries to decode it.
        await #expect(throws: (any Error).self) {
            _ = try await download(with: client(contentType: "text/plain"))
        }
    }
}
