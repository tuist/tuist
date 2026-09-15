import CryptoKit
import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

public struct BinaryCacheArtifact: Codable, Hashable, Sendable {
    public static let manifestName = "BinaryCacheArtifact.json"
    public let name: String
    public let digest: String
    public let fingerprints: [String: String]
    public let architectures: [String: Set<String>]

    public init(name: String, digest: String, fingerprints: [String: String], architectures: [String: Set<String>]) {
        self.name = name
        self.digest = digest
        self.fingerprints = fingerprints
        self.architectures = architectures
    }

    public static func indexKeys(for fingerprints: [String: String]) -> Set<String> {
        guard !fingerprints.isEmpty, fingerprints.count <= BinaryCacheVariant.allCases.count else { return [] }
        let variants = fingerprints.sorted { $0.key < $1.key }
        return Set((1 ..< (1 << variants.count)).map { mask in
            lookupKey(for: Dictionary(uniqueKeysWithValues: variants.enumerated().compactMap { index, pair in
                mask & (1 << index) == 0 ? nil : (pair.key, pair.value)
            }))
        })
    }

    public static func lookupKey(for fingerprints: [String: String]) -> String {
        let input = "xcframework-set-v1|" + fingerprints.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var isValid: Bool {
        Self.isDigest(digest) && !name.isEmpty && !name.contains("/") && !fingerprints.isEmpty
            && fingerprints.allSatisfy { BinaryCacheVariant(rawValue: $0.key) != nil && Self.isDigest($0.value) }
    }

    public static func isDigest(_ value: String) -> Bool {
        [32, 64].contains(value.count) && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    public func satisfies(name: String, fingerprints requested: [String: String]) -> Bool {
        isValid && self.name == name && !requested.isEmpty && requested.allSatisfy { variant, fingerprint in
            guard let variant = BinaryCacheVariant(rawValue: variant) else { return false }
            return fingerprints[variant.rawValue] == fingerprint
                && Set(variant.architectures.map(\.rawValue)).isSubset(of: architectures[variant.rawValue] ?? [])
        }
    }

    public static func coverage(
        at path: AbsolutePath,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> [String: Set<String>] {
        let data = try await fileSystem.readFile(at: path.appending(component: "Info.plist"))
        let info = try PropertyListDecoder().decode(XCFrameworkInfoPlist.self, from: data)
        var result: [String: Set<String>] = [:]
        for variant in BinaryCacheVariant.allCases {
            guard let library = info.libraries.first(where: { variant.matches($0) }) else { continue }
            let libraryPath = path.appending(component: library.identifier).appending(library.path)
            let binaryPath = libraryPath.extension == "framework"
                ? libraryPath.appending(component: libraryPath.basenameWithoutExt) : libraryPath
            guard try await fileSystem.exists(binaryPath) else { continue }
            result[variant.rawValue] = Set(library.architectures.map(\.rawValue))
        }
        return result
    }
}
