import Crypto
import Foundation
import Mockable
import Path
import TuistEnvironment

@Mockable
public protocol DerivedDataLocating {
    func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath
}

public struct DerivedDataLocator: DerivedDataLocating {
    public init() {}

    public func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let root: AbsolutePath
        let usesHash: Bool
        switch try await Environment.current.derivedDataLocation() {
        case .default:
            root = try await Environment.current.derivedDataDirectory()
            usesHash = true
        case let .custom(path):
            root = path
            usesHash = true
        case let .relativeToWorkspace(relativePath):
            root = projectPath.parentDirectory.appending(relativePath)
            usesHash = false
        }

        // When `inspect` runs as an Xcode build/test post-action, these variables point directly
        // at the build's derived data and take precedence over the location inferred from Xcode's
        // preferences.
        if let derivedDataDir = Environment.current.variables["DERIVED_DATA_DIR"] {
            let path = try AbsolutePath(validating: derivedDataDir)
            if path != root {
                return path
            }
        }
        if let buildDir = Environment.current.variables["BUILD_DIR"],
           let buildRoot = Self.derivedDataRoot(from: buildDir),
           buildRoot != root
        {
            return buildRoot
        }

        if usesHash {
            let hash = try XcodeProjectPathHasher.hashString(for: projectPath.pathString)
            return root.appending(component: "\(projectPath.basenameWithoutExt)-\(hash)")
        } else {
            return root.appending(component: projectPath.basenameWithoutExt)
        }
    }

    /// Extracts the derived data root from `BUILD_DIR`.
    /// `BUILD_DIR` is typically `<derived-data-root>/Build/Products/<Configuration>[-<SDK>]`.
    private static func derivedDataRoot(from buildDir: String) -> AbsolutePath? {
        guard let path = try? AbsolutePath(validating: buildDir) else { return nil }
        var current = path
        while !current.isRoot {
            if current.basename == "Products", current.parentDirectory.basename == "Build" {
                return current.parentDirectory.parentDirectory
            }
            current = current.parentDirectory
        }
        return nil
    }
}

// Thanks to https://pewpewthespells.com/blog/xcode_deriveddata_hashes.html for
// the initial Objective-C implementation.
// This is taken from XCLogParser, from Spotify, at:
// https://github.com/spotify/XCLogParser/blob/master/Sources/XcodeHasher/XcodeHasher.swift

enum XcodeProjectPathHasher {
    enum HashingError: Error {
        case invalidPartitioning
    }

    static func hashString(for path: String) throws -> String {
        // Initialize a 28 `String` array since we can't initialize empty `Character`s.
        var result = Array(repeating: "", count: 28)

        let md5 = Insecure.MD5.hash(data: path.data(using: .utf8) ?? Data())
        let digest = Array(md5)

        // Split 16 bytes into two chunks of 8 bytes each.
        let partitions = stride(from: 0, to: digest.count, by: 8).map {
            Array(digest[$0 ..< Swift.min($0 + 8, digest.count)])
        }

        guard let firstHalf = partitions.first,
              let secondHalf = partitions.last
        else {
            throw HashingError.invalidPartitioning
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        var startValue = UInt64(bigEndian: Data(firstHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 13, through: 0, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        startValue = UInt64(bigEndian: Data(secondHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 27, through: 14, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        return result.joined()
    }
}
