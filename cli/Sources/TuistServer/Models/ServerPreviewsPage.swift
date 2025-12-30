import Foundation

public struct ServerPreviewsPage: Equatable {
    public let previews: [ServerPreview]
    public let paginationMetadata: ServerPaginationMetadata
}

extension ServerPreviewsPage {
    init(_ previewsPage: Operations.listPreviews.Output.Ok.Body.jsonPayload) {
        previews = previewsPage.previews.compactMap(ServerPreview.init)
        paginationMetadata = ServerPaginationMetadata(previewsPage.pagination_metadata)
    }
}

#if DEBUG
    extension ServerPreviewsPage {
        public static func test(
            previews: [ServerPreview] = [.test()],
            paginationMetadata: ServerPaginationMetadata = .test()
        ) -> ServerPreviewsPage {
            ServerPreviewsPage(
                previews: previews,
                paginationMetadata: paginationMetadata
            )
        }
    }
#endif
