import Foundation

public struct CIInfo: Equatable {
    public let provider: CIProvider
    public let runId: String?
    public let attemptNumber: String?
    public let projectHandle: String?
    public let host: String?
    /// Workflow/pipeline-scoped identifier preferred for binding a shard plan across jobs.
    /// Set only when the provider exposes a separate cross-job identifier (e.g. CircleCI's
    /// `CIRCLE_WORKFLOW_ID`); `runId` is used for shard binding when this is nil.
    public let pipelineId: String?

    public init(
        provider: CIProvider,
        runId: String? = nil,
        attemptNumber: String? = nil,
        projectHandle: String? = nil,
        host: String? = nil,
        pipelineId: String? = nil
    ) {
        self.provider = provider
        self.runId = runId
        self.attemptNumber = attemptNumber
        self.projectHandle = projectHandle
        self.host = host
        self.pipelineId = pipelineId
    }

    public var shardReference: String? {
        guard let id = pipelineId ?? runId else { return nil }
        if let attemptNumber {
            return "\(provider)-\(id)-\(attemptNumber)"
        }
        return "\(provider)-\(id)"
    }

    #if DEBUG
        public static func test(
            provider: CIProvider = .github,
            runId: String? = "123",
            attemptNumber: String? = nil,
            projectHandle: String? = "test-project",
            host: String? = nil,
            pipelineId: String? = nil
        ) -> CIInfo {
            CIInfo(
                provider: provider,
                runId: runId,
                attemptNumber: attemptNumber,
                projectHandle: projectHandle,
                host: host,
                pipelineId: pipelineId
            )
        }
    #endif
}
