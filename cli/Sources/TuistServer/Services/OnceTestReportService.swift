import Foundation
import TuistHTTP

public struct OnceTestReportService {
    public init() {}

    public func submit(_ data: Data, fullHandle: String, serverURL: URL) async throws {
        let handles = try FullHandleService().parse(fullHandle)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var payload = try decoder.decode(Operations.createTest.Input.Body.jsonPayload.self, from: data)
        payload.id = payload.id ?? UUIDv7.generate()
        let response = try await Client.authenticated(serverURL: serverURL).createTest(
            path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
            body: .json(payload)
        )
        switch response {
        case .ok: return
        case let .undocumented(code, _):
            throw OnceTestReportError(message: "Tuist rejected the Once shard report (HTTP \(code)).")
        default:
            throw OnceTestReportError(message: "Tuist rejected the Once shard report.")
        }
    }
}

public struct OnceTestReportError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
