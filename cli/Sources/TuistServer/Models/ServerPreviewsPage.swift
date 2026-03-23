#if canImport(TuistSimulator)
    import Foundation

    public struct ServerPreviewsPage: Equatable {
        public let previews: [ServerPreview]
        public let paginationMetadata: ServerPaginationMetadata

        init(previews: [ServerPreview], paginationMetadata: ServerPaginationMetadata) {
            self.previews = previews
            self.paginationMetadata = paginationMetadata
        }

        init(_ previewsPage: Operations.listPreviews.Output.Ok.Body.jsonPayload) throws {
            previews = try previewsPage.previews.map(ServerPreview.init)
            paginationMetadata = ServerPaginationMetadata(previewsPage.pagination_metadata)
        }

        #if DEBUG
            public static func test(
                previews: [ServerPreview] = [.test()],
                paginationMetadata: ServerPaginationMetadata = .test()
            ) -> ServerPreviewsPage {
                ServerPreviewsPage(
                    previews: previews,
                    paginationMetadata: paginationMetadata
                )
            }
        #endif
    }
#endif
