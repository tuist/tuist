import Foundation

public struct ServerPaginationMetadata: Equatable {
    public let hasNextPage: Bool
    public let hasPreviousPage: Bool
    public let currentPage: Int?
    public let pageSize: Int
    public let totalCount: Int
    public let totalPages: Int?
}

extension ServerPaginationMetadata {
    init(_ paginationMetadata: Components.Schemas.PaginationMetadata) {
        hasNextPage = paginationMetadata.has_next_page
        hasPreviousPage = paginationMetadata.has_previous_page
        currentPage = paginationMetadata.current_page
        pageSize = paginationMetadata.page_size
        totalCount = paginationMetadata.total_count
        totalPages = paginationMetadata.total_pages
    }
}

#if DEBUG
    extension ServerPaginationMetadata {
        public static func test(
            hasNextPage: Bool = true,
            hasPreviousPage: Bool = false,
            currentPage: Int? = 1,
            pageSize: Int = 20,
            totalCount: Int = 100,
            totalPages: Int? = 5
        ) -> ServerPaginationMetadata {
            ServerPaginationMetadata(
                hasNextPage: hasNextPage,
                hasPreviousPage: hasPreviousPage,
                currentPage: currentPage,
                pageSize: pageSize,
                totalCount: totalCount,
                totalPages: totalPages
            )
        }
    }
#endif
