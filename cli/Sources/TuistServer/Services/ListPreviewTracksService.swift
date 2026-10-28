#if canImport(TuistSimulator)
    import Foundation
    import Mockable
    import TuistHTTP

    @Mockable
    public protocol ListPreviewTracksServicing: Sendable {
        func listPreviewTracks(fullHandle: String, serverURL: URL) async throws -> ServerPreviewTrackSummary?
    }

    public struct ListPreviewTracksService: ListPreviewTracksServicing {
        private let makeClient: @Sendable (URL) -> Client

        public init() {
            self.init(makeClient: { Client.authenticated(serverURL: $0) })
        }

        init(makeClient: @escaping @Sendable (URL) -> Client) {
            self.makeClient = makeClient
        }

        public func listPreviewTracks(fullHandle: String, serverURL: URL) async throws -> ServerPreviewTrackSummary? {
            let handles = try FullHandleService().parse(fullHandle)
            let response = try await makeClient(serverURL).listPreviewTracks(
                .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle))
            )
            switch response {
            case let .ok(ok):
                switch ok.body {
                case let .json(summary):
                    return ServerPreviewTrackSummary(
                        totalCount: summary.total_count,
                        tracks: summary.tracks.map { .init(name: $0.name, count: $0.count) }
                    )
                }
            case let .forbidden(response):
                switch response.body {
                case let .json(error): throw ListPreviewsServiceError.forbidden(error.message)
                }
            case let .unauthorized(response):
                switch response.body {
                case let .json(error): throw ListPreviewsServiceError.unauthorized(error.message)
                }
            case let .tooManyRequests(response):
                throw AuthorizationThrottledError(
                    retryAfterSeconds: response.headers.retry_hyphen_after.flatMap(Int.init)
                )
            case .undocumented(statusCode: 404, _):
                return nil
            case let .undocumented(statusCode: statusCode, _):
                throw ListPreviewsServiceError.unknownError(statusCode)
            }
        }
    }
#endif
