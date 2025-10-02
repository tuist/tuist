import Foundation

public struct CIInfo: Equatable {
    public let provider: CIProvider
    public let runId: String?
    public let projectHandle: String?
    public let host: String?

    public init(
        provider: CIProvider,
        runId: String? = nil,
        projectHandle: String? = nil,
        host: String? = nil
    ) {
        self.provider = provider
        self.runId = runId
        self.projectHandle = projectHandle
        self.host = host
    }
}

#if DEBUG
    extension CIInfo {
        public static func test(
            provider: CIProvider = .github,
            runId: String? = "123",
            projectHandle: String? = "test-project",
            host: String? = nil
        ) -> CIInfo {
            CIInfo(
                provider: provider,
                runId: runId,
                projectHandle: projectHandle,
                host: host
            )
        }
    }
#endif
