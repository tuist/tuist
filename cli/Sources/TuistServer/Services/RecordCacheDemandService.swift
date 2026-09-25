import Foundation
import Mockable

@Mockable
public protocol RecordCacheDemandServicing: Sendable {
    func recordCacheDemand(serverURL: URL, accountHandle: String) async throws
}

public enum RecordCacheDemandServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case unauthorized(String)
    case unknownError(Int)

    public var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .unauthorized(message): return message
        case let .unknownError(status): return "Failed to register cache demand: HTTP \(status)."
        }
    }
}

public struct RecordCacheDemandService: RecordCacheDemandServicing {
    public init() {}

    public func recordCacheDemand(serverURL: URL, accountHandle: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let response = try await Client.authenticated(serverURL: serverURL).recordCacheDemand(
                    .init(query: .init(account_handle: accountHandle))
                )
                switch response {
                case .noContent: return
                case let .forbidden(response): throw RecordCacheDemandServiceError.forbidden(try response.body.json.message)
                case let .unauthorized(response): throw RecordCacheDemandServiceError.unauthorized(try response.body.json.message)
                case let .undocumented(statusCode, _): throw RecordCacheDemandServiceError.unknownError(statusCode)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
