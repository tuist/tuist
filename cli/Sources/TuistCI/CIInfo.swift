import Foundation

public struct CIInfo: Equatable {
    public let provider: CIProvider
    public let runId: String?
    public let attemptNumber: String?
    public let projectHandle: String?
    public let host: String?

    public init(
        provider: CIProvider,
        runId: String? = nil,
        attemptNumber: String? = nil,
        projectHandle: String? = nil,
        host: String? = nil
    ) {
        self.provider = provider
        self.runId = runId
        self.attemptNumber = attemptNumber
        self.projectHandle = projectHandle
        self.host = host
    }

    public var shardReference: String? {
        guard let runId else { return nil }
        if let attemptNumber {
            return "\(provider)-\(runId)-\(attemptNumber)"
        }
        return "\(provider)-\(runId)"
    }

    #if DEBUG
        public static func test(
            provider: CIProvider = .github,
            runId: String? = "123",
            attemptNumber: String? = nil,
            projectHandle: String? = "test-project",
            host: String? = nil
        ) -> CIInfo {
            CIInfo(
                provider: provider,
                runId: runId,
                attemptNumber: attemptNumber,
                projectHandle: projectHandle,
                host: host
            )
        }
    #endif
}
