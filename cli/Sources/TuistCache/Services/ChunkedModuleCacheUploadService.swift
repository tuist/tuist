import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import Path
import TuistHTTP
import TuistServer

enum ChunkedModuleCacheUploadError: Error, HTTPStatusCodeError {
    case response(Int)
    case invalidResponse
    case artifactChanged
    case tooManyChunks

    var httpStatusCode: Int {
        if case let .response(status) = self { return status }
        return 500
    }
}

struct ChunkedModuleCacheUploadService: Sendable {
    typealias Send = @Sendable (String, HTTPRequest.Method, Data?, [String: String]) async throws -> (Int, Data)
    private let cacheTokenStore: CacheTokenStoring

    init(cacheTokenStore: CacheTokenStoring = CacheTokenStore.shared) {
        self.cacheTokenStore = cacheTokenStore
    }

    private struct Capabilities: Decodable {
        let version: Int
        let algorithm: String
        let averageChunkBytes: Int
        let seed: Int
        let normalization: Int
        let minimumBlobBytes: Int
        let maximumChunkBytes: Int
        let maximumChunks: Int

        var supported: Bool {
            version == 1 && algorithm == "fastcdc2020" && averageChunkBytes == 524_288 && seed == 0 && normalization == 2
                && minimumBlobBytes == ContentDefinedChunking.maximumBytes
                && maximumChunkBytes == ContentDefinedChunking.maximumBytes && maximumChunks == 16384
        }
    }

    private struct MissingRequest: Encodable { let chunks: [ContentDefinedChunking.Digest] }
    private struct MissingResponse: Decodable { let missing: [ContentDefinedChunking.Digest] }
    private struct CompleteRequest: Encodable {
        let blob: ContentDefinedChunking.Digest
        let chunks: [ContentDefinedChunking.Digest]
    }

    func uploadIfSupported(
        artifactPath: AbsolutePath, accountHandle: String, projectHandle: String,
        hash: String, name: String, cacheCategory: String, serverURL: URL,
        authenticationURL: URL, serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Bool {
        let fileURL = URL(fileURLWithPath: artifactPath.pathString)
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= ContentDefinedChunking.maximumBytes, size <= 2 * 1024 * 1024 * 1024 else { return false }
        guard try ContentDefinedChunking.hasReusableArchiveEntries(fileURL) else { return false }
        let context = Context(
            serverURL: serverURL,
            params: ["account_handle": accountHandle, "project_handle": projectHandle, "kind": "module"],
            authentication: CacheClientAuthenticationMiddleware(
                authenticationURL: authenticationURL, serverAuthenticationController: serverAuthenticationController,
                cacheTokenStore: cacheTokenStore, fullHandle: "\(accountHandle)/\(projectHandle)"
            )
        )
        return try await uploadIfSupported(
            fileURL: fileURL, endpointKey: "\(serverURL.absoluteString)/\(accountHandle)/\(projectHandle)",
            target: ["hash": hash, "name": name, "cache_category": cacheCategory]
        ) { operation, method, data, extra in
            try await context.send(operation, method: method, data: data, extra: extra)
        }
    }

    func uploadIfSupported(
        fileURL: URL,
        endpointKey: String,
        target: [String: String],
        send: @escaping Send
    ) async throws -> Bool {
        let supported = await ChunkUploadCapabilities.shared.value(for: endpointKey) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let (status, body) = try? await send("capabilities", .get, nil, [:]), status == 200,
                  let capabilities = try? decoder.decode(Capabilities.self, from: body) else { return false }
            return capabilities.supported
        }
        try Task.checkCancellation()
        guard supported else { return false }
        let artifact = try ContentDefinedChunking.scan(fileURL)
        guard artifact.chunks.count > 1 else { return false }
        let digests = artifact.chunks.map(\.digest)
        let requested = Set(digests)
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        for _ in 0 ..< 2 {
            let (status, body) = try await send("missing", .post, JSONEncoder().encode(MissingRequest(chunks: digests)), [:])
            if await unsupported(status, endpointKey: endpointKey) { return false }
            guard status == 200 else { throw ChunkedModuleCacheUploadError.response(status) }
            let response = try JSONDecoder().decode(MissingResponse.self, from: body)
            guard response.missing.count <= digests.count, Set(response.missing).isSubset(of: requested) else {
                throw ChunkedModuleCacheUploadError.invalidResponse
            }
            var missing = Set(response.missing)
            for chunk in artifact.chunks where missing.remove(chunk.digest) != nil {
                try Task.checkCancellation()
                try input.seek(toOffset: chunk.offset)
                let bytes = try input.read(upToCount: chunk.digest.size) ?? Data()
                guard ContentDefinedChunking.digest(bytes) == chunk.digest
                else { throw ChunkedModuleCacheUploadError.artifactChanged }
                let (status, _) = try await send(
                    "upload",
                    .put,
                    bytes,
                    ["hash": chunk.digest.hash, "size": String(chunk.digest.size)]
                )
                if await unsupported(status, endpointKey: endpointKey) { return false }
                guard status == 204 else { throw ChunkedModuleCacheUploadError.response(status) }
            }
            let (completionStatus, _) = try await send(
                "complete", .post, JSONEncoder().encode(CompleteRequest(blob: artifact.digest, chunks: digests)), target
            )
            if completionStatus == 204 { return true }
            if await unsupported(completionStatus, endpointKey: endpointKey) { return false }
            guard completionStatus == 409 else { throw ChunkedModuleCacheUploadError.response(completionStatus) }
        }
        return false
    }

    private func unsupported(_ status: Int, endpointKey: String) async -> Bool {
        guard [404, 405, 501].contains(status) else { return false }
        await ChunkUploadCapabilities.shared.disable(endpointKey)
        return true
    }

    private struct Context: Sendable {
        private static let probeSession: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            return URLSession(configuration: configuration)
        }()

        let serverURL: URL
        let params: [String: String]
        let authentication: CacheClientAuthenticationMiddleware

        func send(
            _ operation: String,
            method: HTTPRequest.Method,
            data: Data?,
            extra: [String: String]
        ) async throws -> (Int, Data) {
            var path = URLComponents()
            path.path = "/api/cache/chunks/\(operation)"
            path.queryItems = params.merging(extra) { _, new in new }.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = HTTPRequest(method: method, scheme: nil, authority: nil, path: path.string)
            request.headerFields[.contentType] = operation == "upload" ? "application/octet-stream" : "application/json"
            let transport =
                URLSessionTransport(configuration: .init(session: operation == "capabilities" ? Self.probeSession : .shared))
            let (response, body) = try await authentication.intercept(
                request, body: data.map(HTTPBody.init), baseURL: serverURL, operationID: "chunk-\(operation)"
            ) { request, body, baseURL in
                try await transport.send(request, body: body, baseURL: baseURL, operationID: "chunk-\(operation)")
            }
            let bytes: Data
            if let body { bytes = try await Data(collecting: body, upTo: 2 * 1024 * 1024) } else { bytes = Data() }
            return (response.status.code, bytes)
        }
    }
}

private actor ChunkUploadCapabilities {
    static let shared = ChunkUploadCapabilities()
    private var values: [String: (supported: Bool, expires: Date)] = [:]
    private var pending: [String: Task<Bool, Never>] = [:]

    func value(for key: String, load: @escaping @Sendable () async -> Bool) async -> Bool {
        if let value = values[key], value.expires > Date() { return value.supported }
        if let task = pending[key] { return await task.value }
        let task = Task { await load() }
        pending[key] = task
        let supported = await task.value
        pending[key] = nil
        if values.count >= 32 { values.removeAll() }
        values[key] = (supported, Date().addingTimeInterval(300))
        return supported
    }

    func disable(_ key: String) { values[key] = (false, Date().addingTimeInterval(300)) }
}
