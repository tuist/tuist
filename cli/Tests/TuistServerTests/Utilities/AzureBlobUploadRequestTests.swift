import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing

@testable import TuistServer

struct AzureBlobUploadRequestTests {
    @Test func addsBlobTypeHeaderForAzurePutBlobSASURL() throws {
        let url = try #require(URL(
            string: "https://tuiststorage.blob.core.windows.net/tuist/icon.png" +
                "?sv=2020-12-06&sr=b&sp=cw&sig=abc"
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        request.addAzureBlobTypeHeaderIfNeeded()

        #expect(request.value(forHTTPHeaderField: "x-ms-blob-type") == "BlockBlob")
    }

    @Test func doesNotAddBlobTypeHeaderForAzurePutBlockSASURL() throws {
        let url = try #require(URL(
            string: "https://tuiststorage.blob.core.windows.net/tuist/archive.zip" +
                "?comp=block&blockid=abc&sv=2020-12-06&sr=b&sp=cw&sig=abc"
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        request.addAzureBlobTypeHeaderIfNeeded()

        #expect(request.value(forHTTPHeaderField: "x-ms-blob-type") == nil)
    }

    @Test func doesNotAddBlobTypeHeaderForS3PresignedURL() throws {
        let url = try #require(URL(string: "https://s3.example.com/tuist/icon.png?X-Amz-Signature=abc"))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        request.addAzureBlobTypeHeaderIfNeeded()

        #expect(request.value(forHTTPHeaderField: "x-ms-blob-type") == nil)
    }
}
