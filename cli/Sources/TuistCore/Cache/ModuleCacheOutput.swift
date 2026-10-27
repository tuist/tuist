import Foundation

/// A single module (binary) cache transfer operation performed during a run.
///
/// Mirrors the server's `cas_outputs` shape so module cache network analytics
/// (transfer volume, latency, throughput) reuse the same generic surface as the
/// compilation cache. Emitted by the remote cache storage for every artifact
/// downloaded from or uploaded to the remote module cache.
public struct ModuleCacheOutput: Codable, Hashable, Sendable {
    public enum Operation: String, Codable, Hashable, Sendable {
        case download, upload
    }

    /// Whether the artifact was downloaded from or uploaded to the remote cache.
    public let operation: Operation
    /// Name of the target the artifact belongs to.
    public let name: String
    /// Content hash of the cached artifact.
    public let hash: String
    /// Size of the artifact on disk, in bytes.
    public let size: Int
    /// Number of bytes actually transferred over the wire (compressed payload).
    public let compressedSize: Int
    /// Duration of this single transfer operation, in milliseconds.
    public let durationInMs: Int

    public init(
        operation: Operation,
        name: String,
        hash: String,
        size: Int,
        compressedSize: Int,
        durationInMs: Int
    ) {
        self.operation = operation
        self.name = name
        self.hash = hash
        self.size = size
        self.compressedSize = compressedSize
        self.durationInMs = durationInMs
    }

    #if DEBUG
        public static func test(
            operation: Operation = .download,
            name: String = "Target",
            hash: String = "module-cache-transfer-hash",
            size: Int = 1024,
            compressedSize: Int = 512,
            durationInMs: Int = 20
        ) -> Self {
            .init(
                operation: operation,
                name: name,
                hash: hash,
                size: size,
                compressedSize: compressedSize,
                durationInMs: durationInMs
            )
        }
    #endif
}
