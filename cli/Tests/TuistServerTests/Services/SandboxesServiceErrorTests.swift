import Foundation
import OpenAPIRuntime
import Testing

@testable import TuistServer

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
}
