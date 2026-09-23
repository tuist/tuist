import Command
@preconcurrency import FileSystem
import Foundation
import Mockable
import Path
import ZIPFoundation

enum AndroidBundleMetadataServiceError: LocalizedError {
    case aapt2NotFound
    case parsingFailed(AbsolutePath)
    case manifestNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case .aapt2NotFound:
            return
                "aapt2 is required to read APK metadata. Install it via the Android SDK (build-tools) and ensure ANDROID_HOME or ANDROID_SDK_ROOT is set, or that aapt2 is in your PATH."
        case let .parsingFailed(path):
            return "Failed to parse Android bundle metadata from \(path.pathString)."
        case let .manifestNotFound(path):
            return "AndroidManifest.xml not found in the extracted bundle at \(path.pathString)."
        }
    }
}

struct AndroidBundleMetadata: Equatable {
    let packageName: String
    let versionName: String
    let appName: String
}

@Mockable
protocol AndroidBundleMetadataServicing: Sendable {
    func apkMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
    func aabMetadata(fromExtractedContentsAt extractedPath: AbsolutePath) async throws -> AndroidBundleMetadata
}

struct AndroidBundleMetadataService: AndroidBundleMetadataServicing {
    @TaskLocal static var poolLock: PoolLock = .init(capacity: 5)

    private static let androidNamespaceURI = "http://schemas.android.com/apk/res/android"

    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming

    init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
    }

    func apkMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata {
        let aapt2 = try await withTiming("aapt2.resolve") {
            try await resolveAapt2Path()
        }
        rosalindLogger.debug("aapt2 resolved to: \(aapt2)")

        rosalindLogger.debug("apkMetadata(\(path.basename)): waiting on PoolLock")
        try await withHeartbeat("apkMetadata(\(path.basename)) PoolLock acquire", every: 30) {
            await Self.poolLock.acquire()
        }
        rosalindLogger.debug("apkMetadata(\(path.basename)): PoolLock acquired")

        let output: String
        do {
            output = try await withHeartbeat("aapt2 dump badging (\(path.basename))", every: 30) {
                try await withTiming("aapt2 dump badging (\(path.basename))") {
                    try await commandRunner
                        .run(arguments: [aapt2, "dump", "badging", path.pathString])
                        .concatenatedString()
                }
            }
        } catch {
            await Self.poolLock.release()
            rosalindLogger.debug("apkMetadata(\(path.basename)): PoolLock released after error")
            throw error
        }

        await Self.poolLock.release()
        rosalindLogger.debug("apkMetadata(\(path.basename)): PoolLock released")

        let packageName = parseValue(from: output, pattern: "package: name='([^']+)'")
        let versionName = parseValue(from: output, pattern: "versionName='([^']+)'")
        let appName = parseValue(from: output, pattern: "application-label:'([^']+)'")

        guard let packageName else {
            throw AndroidBundleMetadataServiceError.parsingFailed(path)
        }

        return AndroidBundleMetadata(
            packageName: packageName,
            versionName: versionName ?? "1.0",
            appName: appName ?? packageName
        )
    }

    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata {
        try await withTiming("aabMetadata(\(path.basename))") {
            // The metadata lives in exactly two ZIP entries: `base/manifest/AndroidManifest.xml`
            // (a protobuf-encoded manifest, typically ~150 KB) and `base/resources.pb` (the
            // resource table, low single-digit megabytes). Reading them straight out of the
            // archive skips the 1 GB+ full unzip that dominated wall-clock on Linux — where
            // ZIPFoundation's per-chunk `Data(count:)` allocations turn a 4 s macOS extract
            // into a nearly minute-long Linux one.
            let (manifestData, resourcesData) = try await Task.detached(priority: .userInitiated) {
                let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .read)
                guard let manifestEntry = archive["base/manifest/AndroidManifest.xml"] else {
                    throw AndroidBundleMetadataServiceError.manifestNotFound(path)
                }
                var manifest = Data()
                _ = try archive.extract(manifestEntry, bufferSize: 256 * 1024, skipCRC32: true) { chunk in
                    manifest.append(chunk)
                }
                var resources: Data?
                if let resourcesEntry = archive["base/resources.pb"] {
                    var buffer = Data()
                    _ = try archive.extract(resourcesEntry, bufferSize: 1024 * 1024, skipCRC32: true) { chunk in
                        buffer.append(chunk)
                    }
                    resources = buffer
                }
                return (manifest, resources)
            }.value

            return try Self.parseAabMetadata(manifestData: manifestData, resourcesData: resourcesData, source: path)
        }
    }

    func aabMetadata(fromExtractedContentsAt extractedPath: AbsolutePath) async throws -> AndroidBundleMetadata {
        let manifestPath = extractedPath.appending(components: "base", "manifest", "AndroidManifest.xml")
        guard try await fileSystem.exists(manifestPath) else {
            throw AndroidBundleMetadataServiceError.manifestNotFound(extractedPath)
        }

        let manifestData = try await withTiming("aabMetadata read AndroidManifest.xml") {
            try await fileSystem.readFile(at: manifestPath)
        }
        rosalindLogger.debug("aabMetadata AndroidManifest.xml size: \(manifestData.count) bytes")

        var resourcesData: Data?
        let resourcesPath = extractedPath.appending(components: "base", "resources.pb")
        if try await fileSystem.exists(resourcesPath) {
            let data = try await withTiming("aabMetadata read resources.pb") {
                try await fileSystem.readFile(at: resourcesPath)
            }
            rosalindLogger.debug("aabMetadata resources.pb size: \(data.count) bytes")
            resourcesData = data
        }

        return try Self.parseAabMetadata(
            manifestData: manifestData,
            resourcesData: resourcesData,
            source: extractedPath
        )
    }

    /// Shared parser used by both the on-disk `fromExtractedContentsAt:` path and the archive-
    /// streaming `at:` path. Isolating it means the streaming path can hand in raw `Data` without
    /// touching the filesystem, while the disk path continues to work for callers that already
    /// have the AAB extracted.
    fileprivate static func parseAabMetadata(
        manifestData: Data,
        resourcesData: Data?,
        source: AbsolutePath
    ) throws -> AndroidBundleMetadata {
        let xmlNode = try Aapt_Pb_XmlNode(serializedBytes: manifestData)
        let attributes = xmlNode.element.attribute
        let packageName = attributes.first(where: { $0.name == "package" })?.value
        let versionName = attributes.first(where: { $0.name == "versionName" })?.value

        guard let packageName, !packageName.isEmpty else {
            throw AndroidBundleMetadataServiceError.parsingFailed(source)
        }

        let resourceTable: Aapt_Pb_ResourceTable? = try resourcesData.map { try Aapt_Pb_ResourceTable(serializedBytes: $0) }
        let appName = Self.applicationLabel(in: xmlNode, resourceTable: resourceTable)

        return AndroidBundleMetadata(
            packageName: packageName,
            versionName: versionName ?? "1.0",
            appName: appName ?? packageName
        )
    }

    private static func applicationLabel(
        in manifest: Aapt_Pb_XmlNode,
        resourceTable: Aapt_Pb_ResourceTable?
    ) -> String? {
        guard let label = manifest.element.child
            .first(where: { $0.element.name == "application" })?
            .element.attribute
            .first(where: { $0.name == "label" && $0.namespaceUri == Self.androidNamespaceURI })
        else { return nil }

        guard case let .ref(reference) = label.compiledItem.value else {
            return label.value.isEmpty ? nil : label.value
        }

        guard let resourceTable else { return nil }
        return string(withResourceID: reference.id, in: resourceTable)
    }

    private static func string(withResourceID resourceID: UInt32, in resourceTable: Aapt_Pb_ResourceTable) -> String? {
        guard let entry = resourceTable.package
            .first(where: { $0.packageID.id == (resourceID >> 24) & 0xFF })?
            .type.first(where: { $0.typeID.id == (resourceID >> 16) & 0xFF })?
            .entry.first(where: { $0.entryID.id == resourceID & 0xFFFF })
        else { return nil }

        guard let configValue = entry.configValue.first(where: { $0.config.locale.isEmpty })
            ?? entry.configValue.first,
            case let .str(string) = configValue.value.item.value,
            !string.value.isEmpty
        else { return nil }

        return string.value
    }

    private func resolveAapt2Path() async throws -> String {
        let environment = ProcessInfo.processInfo.environment
        for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            guard let value = environment[envVar], !value.isEmpty else { continue }
            let buildToolsDir: AbsolutePath
            do {
                buildToolsDir = try AbsolutePath(validating: value).appending(component: "build-tools")
            } catch { continue }
            guard try await fileSystem.exists(buildToolsDir) else { continue }
            let aapt2Paths = try await fileSystem.glob(directory: buildToolsDir, include: ["*/aapt2"]).collect()
            if let aapt2 = aapt2Paths.sorted(by: { $0.pathString > $1.pathString }).first {
                return aapt2.pathString
            }
        }
        if let path = try? await commandRunner
            .run(arguments: ["/usr/bin/env", "which", "aapt2"])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return path
        }
        throw AndroidBundleMetadataServiceError.aapt2NotFound
    }

    private func parseValue(from output: String, pattern: String) -> String? {
        guard let regex = try? Regex(pattern),
              let match = try? regex.firstMatch(in: output),
              match.output.count > 1,
              let capture = match.output[1].substring
        else { return nil }
        return String(capture)
    }
}
