import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolumeJobsPage = Operations.listRunnerVolumeJobs.Output.Ok.Body.jsonPayload

@Mockable
public protocol ListRunnerVolumeJobsServicing {
    func listRunnerVolumeJobs(accountHandle: String, serverURL: URL, volumeID: String, page: Int, pageSize: Int) async throws
        -> RunnerVolumeJobsPage
}

enum ListRunnerVolumeJobsServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not list jobs for the runner volume due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ListRunnerVolumeJobsService: ListRunnerVolumeJobsServicing {
    public init() {}

    public func listRunnerVolumeJobs(
        accountHandle: String,
        serverURL: URL,
        volumeID: String,
        page: Int,
        pageSize: Int
    ) async throws -> RunnerVolumeJobsPage {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.listRunnerVolumeJobs(.init(
            path: .init(account_handle: accountHandle, volume_id: volumeID),
            query: .init(page: page, page_size: pageSize)
        ))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw ListRunnerVolumeJobsServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw ListRunnerVolumeJobsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ListRunnerVolumeJobsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ListRunnerVolumeJobsServiceError.unknownError(statusCode)
        }
    }
}
