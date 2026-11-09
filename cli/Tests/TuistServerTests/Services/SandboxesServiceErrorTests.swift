import Foundation
import HTTPTypes
import OpenAPIRuntime
import TestCoverageAttribution
import Testing

@testable import TuistServer

@Suite(.coverageAttribution)
struct SandboxesServiceErrorTests {
    @Test func anUndocumentedStatusShowsTheServersMessage() async {
        let payload = UndocumentedPayload(body: HTTPBody(#"{"message":"Sandbox operation failed: :archive_store_unavailable"}"#))

        #expect(
            await SandboxesServiceError.undocumented(500, payload)
                == .refused("Sandbox operation failed: :archive_store_unavailable")
        )
    }

    @Test func aBodyWithoutAMessageFallsBackToTheStatus() async {
        #expect(await SandboxesServiceError
            .undocumented(502, UndocumentedPayload(body: HTTPBody("<html>Bad gateway</html>"))) == .unknownError(502))
        #expect(await SandboxesServiceError.undocumented(500, UndocumentedPayload()) == .unknownError(500))
    }

    @Test func aProxyErrorPageOnADocumentedStatusReportsTheStatusNotTheDecodingFailure() async {
        let decodingFailure = DecodingError.keyNotFound(
            AnyCodingKey("message"),
            .init(codingPath: [], debugDescription: "No value associated with key \"message\".")
        )
        func failed(with status: HTTPResponse.Status) -> ClientError {
            ClientError(
                operationID: "execSandboxCommand",
                operationInput: "",
                response: HTTPResponse(status: status),
                causeDescription: "Unknown",
                underlyingError: decodingFailure
            )
        }

        await #expect(throws: SandboxesServiceError.unknownError(502)) {
            try await SandboxesServiceError.send { () async throws -> Int in throw failed(with: .badGateway) }
        }
        // A success the client could not decode is a different problem, so it keeps its original error.
        await #expect(throws: ClientError.self) {
            try await SandboxesServiceError.send { () async throws -> Int in throw failed(with: .ok) }
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue _: Int) { nil }
}
