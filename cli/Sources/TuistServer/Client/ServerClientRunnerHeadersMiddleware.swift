import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistEnvironment

/// Dispatch attestation selects and accesses a Linux shard plan's local store.
struct ServerClientRunnerHeadersMiddleware: ClientMiddleware {
    private let isLinux: Bool

    init(isLinux: Bool? = nil) {
        #if os(Linux)
            self.isLinux = isLinux ?? true
        #else
            self.isLinux = isLinux ?? false
        #endif
    }

    static let operations: Set<String> = [
        "createShardPlan", "getShard", "startShardUpload", "generateShardUploadURL", "completeShardUpload",
    ]
    static func grant(variables: [String: String]) -> String? {
        guard let value = variables["TUIST_CACHE_SIGNING_GRANT"], !value.isEmpty, value.utf8.count <= 8192,
              value.utf8.allSatisfy({
                  (0x41 ... 0x5A).contains($0) || (0x61 ... 0x7A).contains($0) ||
                      (0x30 ... 0x39).contains($0) || [0x2D, 0x2E, 0x5F].contains($0)
              })
        else { return nil }
        return value
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if isLinux, Self.operations.contains(operationID),
           let grant = Self.grant(variables: Environment.current.variables),
           let header = HTTPField.Name("x-tuist-runner-grant")
        {
            request.headerFields[header] = grant
        }
        return try await next(request, body, baseURL)
    }
}
