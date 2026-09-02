import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public struct StressNewTestsVerdictTestCase: Equatable, Sendable {
    public let name: String
    public let suiteName: String?
    public let moduleName: String
    public let duration: Int?

    public init(name: String, suiteName: String?, moduleName: String, duration: Int?) {
        self.name = name
        self.suiteName = suiteName
        self.moduleName = moduleName
        self.duration = duration
    }
}

@Mockable
public protocol CreateStressNewTestsVerdictServicing {
    func createVerdict(
        fullHandle: String,
        serverURL: URL,
        testCases: [StressNewTestsVerdictTestCase]
    ) async throws -> Components.Schemas.StressNewTestsVerdict
}

enum CreateStressNewTestsVerdictServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The stress verdict could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public struct CreateStressNewTestsVerdictService: CreateStressNewTestsVerdictServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func createVerdict(
        fullHandle: String,
        serverURL: URL,
        testCases: [StressNewTestsVerdictTestCase]
    ) async throws -> Components.Schemas.StressNewTestsVerdict {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.createStressNewTestsVerdict(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        test_cases: testCases.map {
                            .init(
                                duration: $0.duration,
                                module_name: $0.moduleName,
                                name: $0.name,
                                suite_name: $0.suiteName
                            )
                        }
                    )
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CreateStressNewTestsVerdictServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw CreateStressNewTestsVerdictServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateStressNewTestsVerdictServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw CreateStressNewTestsVerdictServiceError.badRequest(error.message)
            }
        case let .tooManyRequests(tooManyRequests):
            throw AuthorizationThrottledError(
                retryAfterSeconds: tooManyRequests.headers.retry_hyphen_after.flatMap(Int.init)
            )
        case let .undocumented(statusCode: statusCode, _):
            throw CreateStressNewTestsVerdictServiceError.unknownError(statusCode)
        }
    }
}
