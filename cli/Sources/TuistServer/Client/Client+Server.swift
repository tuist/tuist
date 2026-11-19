import Foundation
import OpenAPIRuntime
import TuistHTTP

extension Client {
    @TaskLocal public static var additionalMiddlewares: [any ClientMiddleware] = []

    /// Non-GET operations the server treats as idempotent, so a request whose response was lost can be sent again.
    /// `createTest`, `createCommandEvent` and `createCargoBuild` are deduplicated by the client-generated `id`, and a
    /// refresh token presented again within 60 seconds of its exchange returns the same tokens. Servers that predate
    /// those guarantees can record a replayed run twice or refuse a replayed refresh.
    static let idempotentServerOperationIDs: Set<String> = [
        "authenticate",
        "cleanCache",
        "completeAnalyticsArtifactsUploads",
        "completeAnalyticsArtifactsUploadsProject",
        "completeCommitCoverage",
        "connectProjectRepository",
        "createCargoBuild",
        "createCommandEvent",
        "createCoverageUpload",
        "createRunnerShellSession",
        // Each call presigns a new object; one a lost answer leaves unused is deleted with the rest.
        "createSandboxUpload",
        "createStressPlan",
        "createTest",
        "deleteRunnerVolume",
        "exchangeOIDCToken",
        "findMissingCommitListings",
        "findMissingCommits",
        "generateAnalyticsArtifactMultipartUploadURL",
        "generateAnalyticsArtifactMultipartUploadURLProject",
        "generateBuildsMultipartUploadURL",
        "generateCacheArtifactMultipartUploadURL",
        "generatePreviewsMultipartUploadURL",
        "generateShardUploadURL",
        "getCacheToken",
        "refreshToken",
        "startAnalyticsArtifactMultipartUpload",
        "startAnalyticsArtifactMultipartUploadProject",
        "startBuildsMultipartUpload",
        "startCacheArtifactMultipartUpload",
        "startShardUpload",
        "updateOrganization",
        "updateOrganization (2)",
        "updateOrganizationMember",
        "updateProject",
        "updateRunnerProfile",
        "uploadCacheActionItem",
        "uploadCommitListing",
        "uploadCommits",
        "uploadPreviewIcon",
    ]

    private static var serverRetryMiddleware: RetryMiddleware {
        RetryMiddleware(idempotentOperationIDs: idempotentServerOperationIDs)
    }

    /// Tuist client for authenticated sessions
    /// With `streaming`, response bodies arrive as the server sends them; see `TuistURLSessionTransport`.
    public static func authenticated(
        serverURL: URL, authenticationURL: URL? = nil, networkTrustedReports: Bool = false,
        networkTrustedPublishing: Bool = false, streaming: Bool = false
    ) -> Client {
        .init(
            serverURL: serverURL,
            transport: TuistURLSessionTransport(streaming: streaming),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                serverRetryMiddleware,
                RequestIdMiddleware(),
                ServerClientFeatureFlagsHeadersMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientPreviewMiddleware(),
                ServerClientActorHeadersMiddleware(),
                ServerClientRunnerHeadersMiddleware(),
                ServerClientAuthenticationMiddleware(
                    authenticationURL: authenticationURL,
                    networkTrustedReports: networkTrustedReports,
                    networkTrustedPublishing: networkTrustedPublishing
                ),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ] + requestCompressionMiddlewares + additionalMiddlewares
        )
    }

    public static func reporting(serverURL: URL, networkTrusted: Bool) -> Client {
        authenticated(serverURL: serverURL, networkTrustedReports: true, networkTrustedPublishing: networkTrusted)
    }

    /// Innermost, so verbose logging still shows the uncompressed body.
    private static var requestCompressionMiddlewares: [any ClientMiddleware] {
        #if canImport(Darwin)
            [ServerClientRequestCompressionMiddleware()]
        #else
            []
        #endif
    }

    /// Tuist client for unauthenticated sessions
    public static func unauthenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: TuistURLSessionTransport(),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                serverRetryMiddleware,
                RequestIdMiddleware(),
                ServerClientFeatureFlagsHeadersMiddleware(),
                ServerClientPreviewMiddleware(),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ] + additionalMiddlewares
        )
    }
}
