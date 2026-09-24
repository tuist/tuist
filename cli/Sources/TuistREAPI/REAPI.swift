import Crypto
import Foundation
import SwiftProtobuf

public enum REAPI {
    public typealias Digest = Build_Bazel_Remote_Execution_V2_Digest
    public typealias Action = Build_Bazel_Remote_Execution_V2_Action
    public typealias Command = Build_Bazel_Remote_Execution_V2_Command
    public typealias ActionResult = Build_Bazel_Remote_Execution_V2_ActionResult
    public typealias Directory = Build_Bazel_Remote_Execution_V2_Directory
    public typealias Tree = Build_Bazel_Remote_Execution_V2_Tree

    public static func digest(_ data: Data) -> Digest {
        Digest.with {
            $0.hash = hashString(SHA256.hash(data: data))
            $0.sizeBytes = Int64(data.count)
        }
    }

    public static func digest(file: URL) throws -> Digest {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
            size += Int64(data.count)
        }
        return Digest.with {
            $0.hash = hashString(hasher.finalize())
            $0.sizeBytes = size
        }
    }

    private static let hexadecimal = Array("0123456789abcdef".utf8)

    static func hashString(_ digest: SHA256.Digest) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(hexadecimal[Int(byte >> 4)])
            bytes.append(hexadecimal[Int(byte & 15)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func validate(_ digest: Digest) throws {
        let bytes = digest.hash.utf8
        guard digest.sizeBytes >= 0, bytes.count == 64,
              bytes.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) })
        else { throw REAPICacheError.invalidDigest }
    }
}

public enum REAPICacheError: Error, LocalizedError {
    case unsupportedEndpoint
    case unsupportedProxy
    case proxyConnectionFailed
    case invalidDigest
    case corruptBlob
    case invalidTree
    case insufficientSpace
    case transferStalled
    public var errorDescription: String? {
        switch self {
        case .invalidDigest: "The cache returned an invalid content digest."
        case .corruptBlob: "The cache content failed its integrity check."
        case .invalidTree: "The cache artifact has an unsupported layout or an unsafe path or symlink."
        case .insufficientSpace: "The cache artifact exceeds the available local cache budget."
        case .transferStalled: "The cache transfer stopped delivering data."
        case .unsupportedEndpoint: "The cache endpoint does not advertise REAPI caching with SHA-256. Configure a REAPI-capable endpoint."
        case .unsupportedProxy: "REAPI requires a CONNECT proxy URL using the http or https scheme."
        case .proxyConnectionFailed: "The proxy could not establish a connection to the REAPI cache."
        }
    }
}

public protocol REAPICacheStoring: Sendable {
    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult?
    func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws
    func uploadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest>
    func downloadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest>
    /// Accepts verified blobs as they become available; implementations may report batches. The callback
    /// may move the file into its final cache location. Publication failures exclude that blob
    /// from the returned set; cancellation stops the operation. `orderedDigests` prioritizes
    /// inputs needed by early consumers without imposing a completion order.
    func downloadAvailableBlobs(
        _ blobs: [REAPI.Digest: URL],
        orderedDigests: [REAPI.Digest],
        onDownloaded: @escaping @Sendable (REAPI.Digest) async throws -> Void
    ) async throws -> Set<REAPI.Digest>
    func uploadBlobs(_ blobs: [REAPI.Digest: URL]) async throws
    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws
}

extension REAPICacheStoring {
    public func uploadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        try await uploadBlobs(blobs)
        return Set(blobs.keys)
    }

    public func downloadAvailableBlobs(
        _ blobs: [REAPI.Digest: URL],
        orderedDigests _: [REAPI.Digest] = [],
        onDownloaded: @escaping @Sendable (REAPI.Digest) async throws -> Void
    ) async throws -> Set<REAPI.Digest> {
        var published = Set<REAPI.Digest>()
        for digest in try await downloadAvailableBlobs(blobs) {
            do {
                try await onDownloaded(digest)
                published.insert(digest)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
            }
        }
        return published
    }

    public func downloadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        var successful = Set<REAPI.Digest>()
        for (digest, path) in blobs {
            do {
                try await downloadBlob(digest, to: path)
                guard try REAPI.digest(file: path) == digest else { throw REAPICacheError.corruptBlob }
                successful.insert(digest)
            } catch {
                if error is CancellationError { throw error }
            }
        }
        return successful
    }
}
