import Crypto
import Foundation
import TuistServer

struct ChunkedModuleCacheDownloadService: Sendable {
    typealias Send = ChunkedModuleCacheUploadService.Send
    var directory: URL = LocalChunkCache.moduleDirectory
    var cacheTokenStore: CacheTokenStoring = CacheTokenStore.shared

    private struct Manifest: Decodable {
        let blob: ContentDefinedChunking.Digest
        let chunks: [ContentDefinedChunking.Digest]

        var valid: Bool {
            func validDigest(_ digest: ContentDefinedChunking.Digest, maximum: Int) -> Bool {
                (1 ... maximum).contains(digest.size) && digest.hash.utf8.count == 64
                    && digest.hash.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
            }
            return validDigest(blob, maximum: 2 * 1024 * 1024 * 1024) && (1 ... 16384).contains(chunks.count)
                && chunks.allSatisfy { validDigest($0, maximum: ContentDefinedChunking.maximumBytes) }
                && chunks.reduce(0) { $0 + $1.size } == blob.size
        }
    }

    func downloadIfSupported(
        accountHandle: String, projectHandle: String, hash: String, name: String, cacheCategory: String,
        serverURL: URL, authenticationURL: URL, serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data? {
        let context = ChunkedModuleCacheUploadService.Context(
            serverURL: serverURL,
            params: ["account_handle": accountHandle, "project_handle": projectHandle, "kind": "module"],
            authentication: CacheClientAuthenticationMiddleware(
                authenticationURL: authenticationURL, serverAuthenticationController: serverAuthenticationController,
                cacheTokenStore: cacheTokenStore, fullHandle: "\(accountHandle)/\(projectHandle)"
            )
        )
        return try await downloadIfSupported(
            endpointKey: "\(serverURL.absoluteString)/\(accountHandle)/\(projectHandle)",
            target: ["hash": hash, "name": name, "cache_category": cacheCategory]
        ) { operation, method, data, extra in
            try await context.send(operation, method: method, data: data, extra: extra)
        }
    }

    func downloadIfSupported(endpointKey: String, target: [String: String], send: @escaping Send) async throws -> Data? {
        let capabilityKey = endpointKey + "/downloads"
        let supported = await ChunkUploadCapabilities.shared.value(for: capabilityKey) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let (status, bytes) = try? await send("capabilities", .get, nil, [:]), status == 200,
                  let capability = try? decoder.decode(ChunkedModuleCacheUploadService.Capabilities.self, from: bytes)
            else { return false }
            return capability.supported && capability.downloadVersion == 1
        }
        try Task.checkCancellation()
        guard supported else { return nil }
        let (status, bytes) = try await send("manifest", .get, nil, target)
        if [404, 405, 501].contains(status) {
            if status != 404 { await ChunkUploadCapabilities.shared.disable(capabilityKey) }
            return nil
        }
        guard status == 200 else { throw ChunkedModuleCacheUploadError.response(status) }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: bytes), manifest.valid else { return nil }
        let cache = LocalChunkCache(directory: directory, scope: endpointKey)
        var output = Data()
        var hasher = SHA256()
        for start in stride(from: 0, to: manifest.chunks.count, by: 4) {
            try Task.checkCancellation()
            let chunks = Array(manifest.chunks[start ..< min(start + 4, manifest.chunks.count)])
            let pieces = try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
                for (index, digest) in chunks.enumerated() {
                    group.addTask {
                        if let cached = cache.get(digest) { return (index, cached) }
                        let (status, bytes) = try await send(
                            "download",
                            .get,
                            nil,
                            ["hash": digest.hash, "size": String(digest.size)]
                        )
                        if [404, 405, 501].contains(status) {
                            if status != 404 { await ChunkUploadCapabilities.shared.disable(capabilityKey) }
                            return (index, nil)
                        }
                        guard status == 200 else { throw ChunkedModuleCacheUploadError.response(status) }
                        guard ContentDefinedChunking.digest(bytes) == digest else { return (index, nil) }
                        cache.put(digest, bytes: bytes)
                        return (index, bytes)
                    }
                }
                var results = [Data?](repeating: nil, count: chunks.count)
                for try await (index, bytes) in group {
                    results[index] = bytes
                }
                return results
            }
            for piece in pieces {
                guard let piece else { return nil }
                hasher.update(data: piece)
                output.append(piece)
            }
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard output.count == manifest.blob.size, hash == manifest.blob.hash else { return nil }
        try Task.checkCancellation()
        return output
    }
}
