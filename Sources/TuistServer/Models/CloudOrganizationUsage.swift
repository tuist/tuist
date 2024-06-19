import Foundation
import Path

/// Cloud organization usage
public struct CloudOrganizationUsage: Codable {
    public init(
        currentMonthRemoteCacheHits: Int
    ) {
        self.currentMonthRemoteCacheHits = currentMonthRemoteCacheHits
    }

    public let currentMonthRemoteCacheHits: Int
}

extension CloudOrganizationUsage {
    init(_ organizationUsage: Components.Schemas.OrganizationUsage) {
        currentMonthRemoteCacheHits = Int(organizationUsage.current_month_remote_cache_hits)
    }
}

#if DEBUG
    extension CloudOrganizationUsage {
        public static func test(
            currentMonthRemoteCacheHits: Int = 100
        ) -> Self {
            .init(
                currentMonthRemoteCacheHits: currentMonthRemoteCacheHits
            )
        }
    }
#endif
