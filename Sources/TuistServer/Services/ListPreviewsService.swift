import Foundation
import Mockable
import TuistSupport

public enum ListPreviewsDistinctField {
    case bundleIdentifier
}

@Mockable
public protocol ListPreviewsServicing {
    func listPreviews(
        displayName: String?,
        specifier: String?,
        page: Int?,
        pageSize: Int?,
        distinctField: ListPreviewsDistinctField?,
        fullHandle: String,
        serverURL: URL
    ) async throws -> [Preview]
}

public enum ListPreviewsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The previews could not be listed due to an unknown Tuist Cloud response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class ListPreviewsService: ListPreviewsServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func listPreviews(
        displayName: String?,
        specifier: String?,
        page: Int?,
        pageSize: Int?,
        distinctField: ListPreviewsDistinctField?,
        fullHandle: String,
        serverURL: URL
    ) async throws -> [Preview] {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.listPreviews(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    display_name: displayName,
                    specifier: specifier,
                    page_size: pageSize,
                    page: page,
                    distinct_field: distinctField.map {
                        switch $0 {
                        case .bundleIdentifier:
                            .bundle_identifier
                        }
                    }
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(previewsIndex):
                return previewsIndex.previews.compactMap(Preview.init)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListPreviewsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw ListPreviewsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListPreviewsServiceError.unauthorized(error.message)
            }
        }
    }
}
