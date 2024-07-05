import Foundation
import Path

/// Server organization usage
public struct ServerOrganizationUsage: Codable {
    public init(
        currentMonthRemoteCacheHits: Int
    ) {
        self.currentMonthRemoteCacheHits = currentMonthRemoteCacheHits
    }

    public let currentMonthRemoteCacheHits: Int
}

extension ServerOrganizationUsage {
    init(_ organizationUsage: Components.Schemas.OrganizationUsage) {
        currentMonthRemoteCacheHits = Int(organizationUsage.current_month_remote_cache_hits)
    }
}

#if DEBUG
    extension ServerOrganizationUsage {
        public static func test(
            currentMonthRemoteCacheHits: Int = 100
        ) -> Self {
            .init(
                currentMonthRemoteCacheHits: currentMonthRemoteCacheHits
            )
        }
    }
#endif
