import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension URLRequest {
    mutating func addAzureBlobTypeHeaderIfNeeded() {
        guard let url,
              httpMethod == "PUT",
              url.isAzureBlobPutBlobSASURL
        else { return }

        setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
    }
}

private extension URL {
    var isAzureBlobPutBlobSASURL: Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else { return false }

        let query = Dictionary(grouping: queryItems, by: \.name)
            .compactMapValues { $0.first?.value }

        return query["sv"] != nil &&
            query["sig"] != nil &&
            query["sr"] == "b" &&
            query["comp"] != "block"
    }
}
