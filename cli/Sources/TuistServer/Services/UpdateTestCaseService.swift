import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias ServerUpdatedTestCase = Operations.updateTestCase.Output.Ok.Body.jsonPayload

@Mockable
public protocol UpdateTestCaseServicing: Sendable {
    func updateTestCase(
        fullHandle: String,
        testCaseId: String,
        state: ServerTestCaseState?,
        isFlaky: Bool?,
        serverURL: URL
    ) async throws -> ServerUpdatedTestCase
}

public enum ServerTestCaseState: String, Sendable, CaseIterable {
    case enabled
    case muted
    case skipped
}

enum UpdateTestCaseServiceError: LocalizedError {
    case unknownError(Int)
    case badRequest(String)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test case could not be updated due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message):
            return message
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct UpdateTestCaseService: UpdateTestCaseServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func updateTestCase(
        fullHandle: String,
        testCaseId: String,
        state: ServerTestCaseState?,
        isFlaky: Bool?,
        serverURL: URL
    ) async throws -> ServerUpdatedTestCase {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.updateTestCase(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_case_id: testCaseId
                ),
                body: .json(.init(is_flaky: isFlaky, state: state?.rawValue))
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UpdateTestCaseServiceError.badRequest(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UpdateTestCaseServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateTestCaseServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateTestCaseServiceError.unknownError(statusCode)
        }
    }
}

#if DEBUG
    extension ServerUpdatedTestCase {
        public static func test(
            id: String = "test-case-id",
            isFlaky: Bool = false,
            isQuarantined: Bool = false,
            module: Operations.updateTestCase.Output.Ok.Body.jsonPayload.modulePayload = .test(),
            name: String = "testExample",
            state: String = "enabled",
            suite: Operations.updateTestCase.Output.Ok.Body.jsonPayload.suitePayload? = nil,
            url: String = "https://tuist.dev/test-case"
        ) -> Self {
            .init(
                id: id,
                is_flaky: isFlaky,
                is_quarantined: isQuarantined,
                module: module,
                name: name,
                state: state,
                suite: suite,
                url: url
            )
        }
    }

    extension Operations.updateTestCase.Output.Ok.Body.jsonPayload.modulePayload {
        public static func test(
            id: String = "module-id",
            name: String = "TestModule"
        ) -> Self {
            .init(id: id, name: name)
        }
    }

    extension Operations.updateTestCase.Output.Ok.Body.jsonPayload.suitePayload {
        public static func test(
            id: String = "suite-id",
            name: String = "TestSuite"
        ) -> Self {
            .init(id: id, name: name)
        }
    }
#endif
