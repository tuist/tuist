import Crypto
import Foundation
import Path
import TuistAlert
import TuistServer

/// A recorded image ready to upload: its manifest entry and the file the bytes come from.
struct SnapshotImageFile: Equatable, Sendable {
    let path: AbsolutePath
    let manifest: SnapshotImageManifest
}

/// Reads the images a snapshot library recorded, the same way the Gradle plugin's
/// `SnapshotImages` does, so either client uploads a directory alike.
enum SnapshotImages {
    /// Lists every image the suite renders, one name per line, so a run filtered to some tests
    /// reports the others as skipped rather than removed (Sentry's `--all-image-file-names`).
    static let allImageNamesFile = "tuist-all-image-names.txt"

    /// Image transfers are small presigned requests, so their time goes to round trips rather than
    /// bandwidth: a full baseline of thousands of images needs many in flight. URLSession still caps
    /// HTTP/1.1 connections per host (`TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST`).
    static let maxConcurrentTransfers = 32

    static func fileSize(_ path: AbsolutePath) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path.pathString))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// "2.3 MB in 1.4s", for the transfer summaries CI logs keep.
    static func transferSummary(bytes: Int64, duration: Duration) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) in \(seconds(duration))"
    }

    static func seconds(_ duration: Duration) -> String {
        let components = duration.components
        return String(format: "%.1fs", Double(components.seconds) + Double(components.attoseconds) / 1e18)
    }

    /// Roborazzi's compare and verify tasks write these next to the recorded images.
    private static let derivedSuffixes = ["_compare.png", "_actual.png", "_diff.png"]

    static func collect(directory: AbsolutePath) async throws -> [SnapshotImageFile] {
        let root = directory.url.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let files = enumerator.compactMap { $0 as? URL }.filter { url in
            url.pathExtension == "png" && !derivedSuffixes.contains { url.lastPathComponent.hasSuffix($0) }
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        return try files
            .map { url -> SnapshotImageFile in
                let name = url.standardizedFileURL.pathComponents
                    .dropFirst(rootComponents.count).joined(separator: "/")
                return try image(at: directory.appending(try RelativePath(validating: name)), name: name)
            }
            .sorted { $0.manifest.name < $1.manifest.name }
    }

    static func allImageNames(file: AbsolutePath) -> [String]? {
        guard let contents = try? String(contentsOf: file.url, encoding: .utf8) else { return nil }
        var seen = Set<String>()
        return contents.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func image(at path: AbsolutePath, name: String) throws -> SnapshotImageFile {
        let data = try Data(contentsOf: path.url)
        let dimensions = pngDimensions(data)
        let metadata = SnapshotMetadata.read(image: path)
        return SnapshotImageFile(
            path: path,
            manifest: SnapshotImageManifest(
                name: name,
                contentHash: contentHash(data),
                width: dimensions?.width,
                height: dimensions?.height,
                displayName: metadata.displayName,
                group: metadata.group,
                tags: metadata.tags,
                diffThreshold: metadata.diffThreshold
            )
        )
    }

    /// The lowercase hex SHA-256 the server addresses images by.
    static func contentHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The width and height from a PNG's IHDR chunk, which always comes first.
    static func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data.prefix(24))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count == 24, Array(bytes[0 ..< 8]) == signature, Array(bytes[12 ..< 16]) == Array("IHDR".utf8)
        else { return nil }
        let integer = { (offset: Int) in bytes[offset ..< offset + 4].reduce(0) { $0 << 8 | Int($1) } }
        return (integer(16), integer(20))
    }
}

/// The JSON file next to an image, in the format Sentry's snapshot uploads use, which
/// the tuist/snapshots library writes, as do SnapshotPreviews and ComposablePreviewScanner setups.
struct SnapshotMetadata: Equatable {
    var displayName: String?
    var group: String?
    var tags: [String: String] = [:]
    var diffThreshold: Double?

    static func read(image: AbsolutePath) -> SnapshotMetadata {
        let file = image.parentDirectory.appending(component: "\(image.basenameWithoutExt).json")
        guard let data = try? Data(contentsOf: file.url) else { return SnapshotMetadata() }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AlertController.current
                .warning(.alert("Ignoring the snapshot metadata in \(file.basename), which isn't a JSON object."))
            return SnapshotMetadata()
        }
        return SnapshotMetadata(
            displayName: json["display_name"] as? String,
            group: json["group"] as? String,
            tags: tags(json["tags"]),
            diffThreshold: (json["diff_threshold"] as? NSNumber)?.doubleValue
        )
    }

    /// Sentry accepts tags as an object or a list; values become strings either way.
    private static func tags(_ value: Any?) -> [String: String] {
        switch value {
        case let object as [String: Any]:
            return object.mapValues { value in
                switch value {
                case let string as String: return string
                case let number as NSNumber: return number.stringValue
                default:
                    return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
                }
            }
        case let list as [Any]:
            return Dictionary(list.compactMap { $0 as? String }.map { ($0, "true") }, uniquingKeysWith: { first, _ in first })
        default:
            return [:]
        }
    }
}
