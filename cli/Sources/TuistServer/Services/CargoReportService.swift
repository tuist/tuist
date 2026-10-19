import Foundation
import TuistHTTP

/// Cargo reports use the same credentials as the other Tuist integrations.
public struct CargoReportService {
    public init() {}

    public func submit(_ data: Data, fullHandle: String, serverURL: URL, kind: String) async throws {
        let handles = try FullHandleService().parse(fullHandle)
        let client = Client.authenticated(serverURL: serverURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if kind == "builds" {
            let payload = try decoder.decode(Operations.createCargoBuild.Input.Body.jsonPayload.self, from: data)
            let response = try await client.createCargoBuild(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(payload)
            )
            guard case .created = response else { throw CargoReportError(message: "Tuist rejected the Cargo build report.") }
        } else {
            let payload = try decoder.decode(Operations.createTest.Input.Body.jsonPayload.self, from: data)
            let response = try await client.createTest(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(payload)
            )
            guard case .ok = response else { throw CargoReportError(message: "Tuist rejected the Cargo test report.") }
        }
    }
}

public struct CargoReportError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
