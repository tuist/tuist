import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias ServerTestCaseEvent = Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload.eventsPayloadPayload

@Mockable
public protocol ListTestCaseEventsServicing: Sendable {
    func listTestCaseEvents(
        fullHandle: String,
        testCaseId: String,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload
}

enum ListTestCaseEventsServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test case events could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListTestCaseEventsService: ListTestCaseEventsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func listTestCaseEvents(
        fullHandle: String,
        testCaseId: String,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCaseEvents(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle,
                test_case_id: testCaseId
            ),
            query: .init(
                page_size: pageSize,
                page: page
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListTestCaseEventsServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListTestCaseEventsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestCaseEventsServiceError.unknownError(statusCode)
        }
    }
}

#if DEBUG
    extension ServerTestCaseEvent {
        public static func test(
            eventType: Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload.eventsPayloadPayload
                .event_typePayload = .marked_flaky,
            insertedAt: Int = 1_700_000_000,
            actor: Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload.eventsPayloadPayload.actorPayload? = nil
        ) -> Self {
            .init(
                actor: actor,
                event_type: eventType,
                inserted_at: insertedAt
            )
        }
    }
#endif
