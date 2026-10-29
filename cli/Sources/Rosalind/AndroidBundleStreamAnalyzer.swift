import Crypto
import Foundation
import Mockable
import Path
import ZIPFoundation

/// Result of analyzing an Android bundle (`.aab` / `.apk`) directly from its ZIP archive without
/// extracting it to disk.
struct AndroidBundleStreamAnalysis: Equatable {
    let installSize: Int
    let downloadSize: Int
    let artifact: AppBundleArtifact
}

@Mockable
protocol AndroidBundleStreamAnalyzing: Sendable {
    func analyzeAab(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis
    func analyzeApk(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis
}

/// Reads an Android bundle by iterating the ZIP central directory and hashing each entry's
/// decompressed bytes as they stream by. Nothing is written to disk. On Linux this avoids the
/// 6,000+ per-file writes that dominate `FileManager.unzipItem` wall-clock; on macOS it also
/// beats disk extraction because it skips the write path entirely.
///
/// AAB analysis applies a Play Store–style device filter while walking the archive, so
/// `installSize` and `downloadSize` approximate what a real device actually installs and
/// downloads rather than the whole publishing container. The reference device matches the
/// spec bundletool was invoked with before the streaming rewrite: 64-bit Arm, xxhdpi English,
/// SDK 34.
struct AndroidBundleStreamAnalyzer: AndroidBundleStreamAnalyzing {
    /// 1 MB per inflate call. ZIPFoundation on Linux allocates a fresh `Data(count:)` per output
    /// chunk, so a larger chunk amortises the allocation cost across a much bigger inflate step.
    /// 1 MB is well below the working set of realistic entries (dex, so, arsc) so the compiler
    /// keeps this on the fast path.
    private static let inflateBufferSize = 1024 * 1024

    /// The ABI the reference device downloads. arm64-v8a covers the overwhelming majority of
    /// modern Android devices and matches the Play Console's "recommended" split.
    private static let referenceAbi = "arm64-v8a"

    /// Density buckets that survive the filter. `xxhdpi` is the reference bucket; `anydpi` and
    /// `nodpi` are qualifier-agnostic buckets bundletool always includes.
    private static let referenceDensities: Set<String> = ["xxhdpi", "anydpi", "nodpi"]

    /// Densities that are stripped when a resource dir explicitly targets a non-reference bucket.
    /// A directory qualifier that doesn't appear here is treated as reference-neutral (kept).
    private static let strippedDensities: Set<String> = [
        "ldpi", "mdpi", "hdpi", "xhdpi", "xxxhdpi", "tvdpi",
    ]

    /// Two-letter language codes that survive the filter. Anything else language-qualified is
    /// dropped; unqualified dirs are always kept.
    private static let referenceLanguages: Set<String> = ["en"]

    /// AAB analysis: walk `base/` and keep only entries that a Play Store split for the
    /// reference device would actually deliver.
    func analyzeAab(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis {
        try await stream(archiveAt: path, prefix: "base/", filter: .referenceDevice, rootName: rootName)
    }

    /// APK analysis: everything in the archive is part of the install, so no prefix filter.
    func analyzeApk(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis {
        try await stream(archiveAt: path, prefix: nil, filter: .none, rootName: rootName)
    }

    private func stream(
        archiveAt path: AbsolutePath,
        prefix: String?,
        filter: EntryFilter,
        rootName: String
    ) async throws -> AndroidBundleStreamAnalysis {
        try await Task.detached(priority: .userInitiated) {
            let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .read)
            let root = TreeNode(name: rootName)
            var installSize = 0
            var downloadSize = 0
            for entry in archive where entry.type == .file {
                let entryPath: String
                if let prefix {
                    guard entry.path.hasPrefix(prefix), entry.path.count > prefix.count else { continue }
                    entryPath = String(entry.path.dropFirst(prefix.count))
                } else {
                    entryPath = entry.path
                }
                let components = entryPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard !components.isEmpty else { continue }
                guard Self.keep(components: components, filter: filter) else { continue }

                var hasher = SHA256()
                var bytes = 0
                _ = try archive.extract(entry, bufferSize: Self.inflateBufferSize, skipCRC32: true) { data in
                    hasher.update(data: data)
                    bytes += data.count
                }
                let digest = hasher.finalize()
                let shasum = Self.hex(digest)
                installSize += bytes
                downloadSize += Int(entry.compressedSize)
                root.insert(components: components, size: bytes, shasum: shasum, type: Self.classify(components.last!))
            }
            let artifact = root.render(pathPrefix: rootName)
            return AndroidBundleStreamAnalysis(
                installSize: installSize,
                downloadSize: downloadSize,
                artifact: artifact
            )
        }.value
    }

    /// Applies the reference-device filter to a `base/`-relative path split into components.
    /// The rules mirror how bundletool splits an AAB for a device with `supportedAbis`
    /// [arm64-v8a], `screenDensity` xxhdpi and `supportedLocales` [en]:
    ///
    /// - `lib/{abi}/*` survives only for `arm64-v8a`. Every other ABI is dead weight for the
    ///   reference device and is the single biggest driver of the "double size" report before
    ///   this filter existed.
    /// - `res/*` is inspected as a qualifier string. If it names a density bucket other than the
    ///   reference set the whole dir is dropped; if it names a language other than `en` the
    ///   whole dir is dropped. Unqualified and reference-matching dirs pass through.
    /// - The AAB-only protobuf metadata under `base/` — `resources.pb`, `native.pb`,
    ///   `assets.pb`, and `manifest/AndroidManifest.xml` — is dropped. bundletool doesn't ship
    ///   those files: it converts `resources.pb` into a filtered `resources.arsc` split across
    ///   the master and density APKs, `manifest/AndroidManifest.xml` into a binary
    ///   `AndroidManifest.xml` per split, and drops `native.pb`/`assets.pb` entirely. We can't
    ///   regenerate those device-format files without a JVM, so we accept the ~1 MB
    ///   underestimate their generated equivalents would add and stay close to bundletool's
    ///   reported numbers instead of overshooting by the ~6 MB of protobuf that never ships.
    /// - Everything else (`dex`, `assets`, `root`, etc.) is kept because those bytes ship to
    ///   every device unchanged.
    static func keep(components: [String], filter: EntryFilter) -> Bool {
        guard filter == .referenceDevice else { return true }
        guard let head = components.first else { return true }

        switch head {
        case "lib":
            // lib/<abi>/<file>. If we don't have an ABI segment yet, keep so the walker can drill in.
            guard components.count >= 2 else { return true }
            return components[1] == referenceAbi
        case "res":
            // res/<qualified-dir>/<file>. res/<file> (no qualifier dir) is fine.
            guard components.count >= 2 else { return true }
            return keepResourceQualifier(components[1])
        case "resources.pb", "native.pb", "assets.pb":
            return false
        case "manifest":
            return false
        default:
            return true
        }
    }

    /// A resource directory name like `drawable-xxhdpi-v4` or `values-fr-rCA`. Split on `-` and
    /// look at the qualifier tokens after the resource type. A directory is dropped if it names
    /// a density bucket that is not in the reference set, or a language that is not `en`. A
    /// qualifier we don't recognise is treated as neutral (kept) so obscure Android qualifiers
    /// don't accidentally strip content.
    private static func keepResourceQualifier(_ dirName: String) -> Bool {
        let tokens = dirName.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count > 1 else { return true }

        var index = 1
        while index < tokens.count {
            let token = tokens[index]

            if strippedDensities.contains(token) { return false }
            if referenceDensities.contains(token) { index += 1; continue }

            if isLanguageQualifier(token) {
                if !referenceLanguages.contains(token) { return false }
                // Skip an optional region qualifier like `-rGB` immediately after `-en`.
                if index + 1 < tokens.count, isRegionQualifier(tokens[index + 1]) {
                    index += 2
                    continue
                }
                index += 1
                continue
            }

            index += 1
        }
        return true
    }

    /// A two-letter lowercase segment like `en`, `fr`, `de`. Android's other qualifiers either
    /// have a different letter count (`land`, `port`, `v21`, `sw600dp`) or start with digits.
    private static func isLanguageQualifier(_ token: String) -> Bool {
        guard token.count == 2 else { return false }
        return token.allSatisfy { $0.isLowercase && $0.isLetter }
    }

    /// A region qualifier is `r` followed by two uppercase letters (`rUS`, `rGB`).
    private static func isRegionQualifier(_ token: String) -> Bool {
        guard token.count == 3, token.hasPrefix("r") else { return false }
        return token.dropFirst().allSatisfy { $0.isUppercase && $0.isLetter }
    }

    /// Matches `Rosalind.artifactType(for:isAndroid:)` for the Android branch. Kept in sync by
    /// hand rather than shared: this analyzer is the only Android caller now, and hoisting a
    /// helper into `Rosalind` would create an import cycle with `AppBundleArtifact`.
    private static func classify(_ filename: String) -> AppBundleArtifact.ArtifactType {
        guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return .file }
        let ext = String(filename[filename.index(after: dot)...])
        switch ext {
        case "otf", "ttc", "ttf", "woff": return .font
        case "strings", "xcstrings": return .localization
        case "dex", "so": return .binary
        case "arsc": return .asset
        default: return .file
        }
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    enum EntryFilter: Equatable {
        /// Keep every entry that survives the prefix check.
        case none
        /// Apply the Play Store split rules for the reference device.
        case referenceDevice
    }
}

/// In-memory tree accumulator that mirrors what `Rosalind.traverse` used to build against a
/// directory on disk. Directory shasums combine children shasums the way `ShasumCalculator`
/// already did: SHA-256 of the sorted-shasum concatenation.
private final class TreeNode {
    let name: String
    var children: [String: TreeNode] = [:]
    var isFile: Bool = false
    var fileSize: Int = 0
    var fileShasum: String = ""
    var fileType: AppBundleArtifact.ArtifactType = .file

    init(name: String) {
        self.name = name
    }

    func insert(components: [String], size: Int, shasum: String, type: AppBundleArtifact.ArtifactType) {
        var cursor = self
        for (index, component) in components.enumerated() {
            if index == components.count - 1 {
                let leaf = TreeNode(name: component)
                leaf.isFile = true
                leaf.fileSize = size
                leaf.fileShasum = shasum
                leaf.fileType = type
                cursor.children[component] = leaf
            } else {
                if let existing = cursor.children[component] {
                    cursor = existing
                } else {
                    let node = TreeNode(name: component)
                    cursor.children[component] = node
                    cursor = node
                }
            }
        }
    }

    func render(pathPrefix: String) -> AppBundleArtifact {
        if isFile {
            return AppBundleArtifact(
                artifactType: fileType,
                path: pathPrefix,
                size: fileSize,
                shasum: fileShasum,
                children: nil
            )
        }
        let childNodes = children.keys.sorted().map { key -> AppBundleArtifact in
            children[key]!.render(pathPrefix: "\(pathPrefix)/\(key)")
        }
        let totalSize = childNodes.reduce(0) { $0 + $1.size }
        let combined = childNodes.map(\.shasum).sorted().joined()
        let digest = SHA256.hash(data: Data(combined.utf8))
        return AppBundleArtifact(
            artifactType: .directory,
            path: pathPrefix,
            size: totalSize,
            shasum: digest.map { String(format: "%02x", $0) }.joined(),
            children: childNodes
        )
    }
}
