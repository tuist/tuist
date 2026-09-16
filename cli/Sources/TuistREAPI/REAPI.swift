import CryptoKit
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
            $0.hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
            $0.hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            $0.sizeBytes = size
        }
    }

    public static func validate(_ digest: Digest) throws {
        guard digest.sizeBytes >= 0, digest.hash.count == 64,
              digest.hash.allSatisfy({ "0123456789abcdef".contains($0) })
        else { throw REAPICacheError.invalidDigest }
    }
}

public enum REAPICacheError: Error {
    case invalidDigest
    case corruptBlob
    case invalidTree
    case insufficientSpace
}

public protocol REAPICacheStoring: Sendable {
    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult?
    func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws
    func uploadBlobs(_ blobs: [REAPI.Digest: URL]) async throws
    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws
}
