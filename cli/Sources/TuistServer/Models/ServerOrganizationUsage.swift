import Foundation

/// Server organization usage
public struct ServerOrganizationUsage: Codable {
    public init(
        currentMonthRemoteCacheHits: Int,
        currentMonthComputeUnitMinutes: Int,
        currentMonthLLMTokens: LLMTokens
    ) {
        self.currentMonthRemoteCacheHits = currentMonthRemoteCacheHits
        self.currentMonthComputeUnitMinutes = currentMonthComputeUnitMinutes
        self.currentMonthLLMTokens = currentMonthLLMTokens
    }

    public let currentMonthRemoteCacheHits: Int
    public let currentMonthComputeUnitMinutes: Int
    public let currentMonthLLMTokens: LLMTokens

    public struct LLMTokens: Codable {
        public init(input: Int, output: Int, total: Int) {
            self.input = input
            self.output = output
            self.total = total
        }

        public let input: Int
        public let output: Int
        public let total: Int
    }
}

extension ServerOrganizationUsage {
    init(_ organizationUsage: Components.Schemas.OrganizationUsage) {
        currentMonthRemoteCacheHits = Int(organizationUsage.current_month_remote_cache_hits)
        currentMonthComputeUnitMinutes = Int(organizationUsage.current_month_compute_unit_minutes)
        currentMonthLLMTokens = .init(
            input: Int(organizationUsage.current_month_llm_tokens.input),
            output: Int(organizationUsage.current_month_llm_tokens.output),
            total: Int(organizationUsage.current_month_llm_tokens.total)
        )
    }
}

#if DEBUG
    extension ServerOrganizationUsage {
        public static func test(
            currentMonthRemoteCacheHits: Int = 100,
            currentMonthComputeUnitMinutes: Int = 0,
            currentMonthLLMTokens: LLMTokens = .init(input: 0, output: 0, total: 0)
        ) -> Self {
            .init(
                currentMonthRemoteCacheHits: currentMonthRemoteCacheHits,
                currentMonthComputeUnitMinutes: currentMonthComputeUnitMinutes,
                currentMonthLLMTokens: currentMonthLLMTokens
            )
        }
    }
#endif
