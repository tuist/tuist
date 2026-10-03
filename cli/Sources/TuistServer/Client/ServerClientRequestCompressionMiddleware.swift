#if canImport(Darwin)
    import Foundation
    import HTTPTypes
    import OpenAPIRuntime

    /// Compresses the large request bodies of the operations that carry code coverage: a test
    /// run's line data serializes to megabytes of JSON that shrink by an order of magnitude, and
    /// would otherwise exceed the server's and proxies' request size limits on large codebases.
    ///
    /// The body is raw DEFLATE (`Content-Encoding: deflate`), which the server inflates. A server
    /// that predates that support cannot parse the body and responds with a 400 or 415 before
    /// creating anything, so the uncompressed body is sent again.
    struct ServerClientRequestCompressionMiddleware: ClientMiddleware {
        static let compressedOperations: Set<String> = ["createTest"]
        static let minimumSize = 1_000_000

        func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            guard Self.compressedOperations.contains(operationID), let body else {
                return try await next(request, body, baseURL)
            }

            let data = try await Data(collecting: body, upTo: .max)
            guard data.count >= Self.minimumSize,
                  let compressed = try? (data as NSData).compressed(using: .zlib) as Data
            else {
                return try await next(request, HTTPBody(data), baseURL)
            }

            var compressedRequest = request
            compressedRequest.headerFields[.contentEncoding] = "deflate"
            compressedRequest.headerFields[.contentLength] = nil
            let (response, responseBody) = try await next(compressedRequest, HTTPBody(compressed), baseURL)
            guard [400, 415].contains(response.status.code) else { return (response, responseBody) }
            return try await next(request, HTTPBody(data), baseURL)
        }
    }
#endif
