import Foundation
import Mockable
import TuistHTTP
import TuistSimulator

public enum ListPreviewsDistinctField {
    case bundleIdentifier
}

@Mockable
public protocol ListPreviewsServicing: Sendable {
    func listPreviews(
        displayName: String?,
        specifier: String?,
        supportedPlatforms: [DestinationType],
        page: Int?,
        pageSize: Int?,
        distinctField: ListPreviewsDistinctField?,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreviewsPage
}

public enum ListPreviewsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The previews could not be listed due to an unknown Tuist response of \(statusCode)."
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
        supportedPlatforms: [DestinationType],
        page: Int?,
        pageSize: Int?,
        distinctField: ListPreviewsDistinctField?,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreviewsPage {
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
                    supported_platforms: supportedPlatforms.map(Components.Schemas.PreviewSupportedPlatform.init),
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
                return ServerPreviewsPage(previewsIndex)
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

extension Components.Schemas.PreviewSupportedPlatform {
    init(_ supportedPlatform: DestinationType) {
        switch supportedPlatform {
        case let .device(platform):
            switch platform {
            case .iOS:
                self = .ios
            case .macOS:
                self = .macos
            case .tvOS:
                self = .tvos
            case .watchOS:
                self = .watchos
            case .visionOS:
                self = .visionos
            }
        case let .simulator(platform):
            switch platform {
            case .iOS:
                self = .ios_simulator
            case .macOS:
                self = .macos
            case .tvOS:
                self = .tvos_simulator
            case .watchOS:
                self = .watchos_simulator
            case .visionOS:
                self = .visionos_simulator
            }
        }
    }
}
