import Foundation
import OpenAPIRuntime
import TuistHTTP

extension Client {
    @TaskLocal public static var additionalMiddlewares: [any ClientMiddleware] = []

    /// Non-GET operations the server treats as idempotent, so a request whose response was lost can be sent again.
    static let idempotentServerOperationIDs: Set<String> = [
        "authenticate",
        "cleanCache",
        "clearRunnerVolume",
        "completeAnalyticsArtifactsUploads",
        "completeAnalyticsArtifactsUploadsProject",
        "completeCommitCoverage",
        "connectProjectRepository",
        "createCoverageUpload",
        "createRunnerShellSession",
        "createStressPlan",
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

    /// `createTest` answers 503 both before writing, when a shard plan is not visible yet (with `Retry-After`), and
    /// after creating the run, when its processing could not be scheduled.
    private static var serverRetryMiddleware: RetryMiddleware {
        RetryMiddleware(
            idempotentOperationIDs: idempotentServerOperationIDs,
            operationIDsAnsweringServiceUnavailableAfterWriting: ["createTest"]
        )
    }

    /// Tuist client for authenticated sessions
    public static func authenticated(
        serverURL: URL, authenticationURL: URL? = nil, networkTrustedReports: Bool = false,
        networkTrustedPublishing: Bool = false
    ) -> Client {
        .init(
            serverURL: serverURL,
            transport: TuistURLSessionTransport(),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                serverRetryMiddleware,
                RequestIdMiddleware(),
                ServerClientFeatureFlagsHeadersMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientActorHeadersMiddleware(),
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
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
