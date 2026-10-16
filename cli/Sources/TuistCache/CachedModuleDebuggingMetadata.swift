import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
public protocol CachedModuleDebuggingMetadataReading {
    func sourceMappings(artifact: AbsolutePath, target: GraphTarget) async throws -> [DebuggerSourceMapping]?
}

public struct CachedModuleDebuggingMetadataReader: CachedModuleDebuggingMetadataReading {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func sourceMappings(artifact: AbsolutePath, target: GraphTarget) async throws -> [DebuggerSourceMapping]? {
        try await CachedModuleDebuggingMetadata.sourceMappings(at: artifact, for: target, fileSystem: fileSystem)
    }
}

/// Source identities accompany debug information inside each XCFramework slice. No source bytes are published.
public struct CachedModuleDebuggingMetadata: Codable, Equatable, Sendable {
    public static let fileName = "tuist-debugging.json"
    private static let currentVersion = 1
    private static let maximumSize = 4 * 1024 * 1024

    public let version: Int
    public let moduleName: String
    public let sourceRoot: AbsolutePath
    public let sources: [String: String]
    public let sourcePaths: [String: String]
    public let debugPaths: [String: String]

    public static func capture(
        target: GraphTarget,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> Self {
        try Task.checkCancellation()
        let paths = Set(target.target.sources.map(\.path))
            .union(target.target.headers?.public ?? [])
            .union(target.target.headers?.private ?? [])
            .union(target.target.headers?.project ?? [])
        let contentHasher = ContentHasher(fileSystem: fileSystem)
        var sources: [String: String] = [:]
        var sourcePaths: [String: String] = [:]
        for path in paths.sorted() {
            try Task.checkCancellation()
            let relative = path.relative(to: target.project.sourceRootPath).pathString
            sources[relative] = try await contentHasher.hash(path: path)
            sourcePaths[relative] = try await fileSystem.resolveSymbolicLink(path).pathString
        }
        return Self(
            version: currentVersion,
            moduleName: target.target.productName,
            sourceRoot: target.project.sourceRootPath,
            sources: sources,
            sourcePaths: sourcePaths,
            debugPaths: [:]
        )
    }

    /// Uses the paths actually present in DWARF, including scanner prefix maps and canonicalized roots.
    public func recording(debugSources: Set<String>, prefixMappings: [[String: String]] = []) throws -> Self {
        var paths: [String: String] = [:]
        for relative in sources.keys.sorted() {
            let original = sourceRoot.appending(try RelativePath(validating: relative)).pathString
            var candidates: Set<String> = [original]
            if let canonical = sourcePaths[relative] { candidates.insert(canonical) }
            for mappings in prefixMappings {
                for (alias, root) in mappings {
                    let root = try AbsolutePath(validating: root).pathString
                    let prefix = root == "/" ? root : root + "/"
                    for source in [original, sourcePaths[relative]].compactMap({ $0 }) where source.hasPrefix(prefix) {
                        candidates.insert((alias.hasSuffix("/") ? alias : alias + "/") + source.dropFirst(prefix.count))
                    }
                }
            }
            let matches = candidates.intersection(debugSources)
            guard matches.count <= 1 else { throw DebuggingMetadataError.ambiguousSource(relative) }
            if let path = matches.first { paths[relative] = path }
        }
        guard sources.isEmpty || !paths.isEmpty else { throw DebuggingMetadataError.missingSources }
        guard Set(paths.values).count == paths.count
        else { throw DebuggingMetadataError.ambiguousSource("overlapping compiler prefix mappings") }
        let metadata = Self(
            version: version,
            moduleName: moduleName,
            sourceRoot: sourceRoot,
            sources: sources,
            sourcePaths: sourcePaths,
            debugPaths: paths
        )
        guard try JSONEncoder().encode(metadata).count <= Self.maximumSize else { throw DebuggingMetadataError.excessiveSize }
        return metadata
    }

    /// Missing, incompatible or ambiguous metadata must retain sources, rather than map a different module's files.
    public static func sourceMappings(
        at artifact: AbsolutePath,
        for target: GraphTarget,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> [DebuggerSourceMapping]? {
        try Task.checkCancellation()
        let artifactRoot = try await fileSystem.resolveSymbolicLink(artifact)
        guard let infoData = try await metadataData(
            at: artifact.appending(component: "Info.plist"),
            enclosedBy: artifactRoot,
            fileSystem: fileSystem
        ) else { return nil }
        let info = try PropertyListDecoder().decode(XCFrameworkInfoPlist.self, from: infoData)
        guard !info.libraries.isEmpty else { return nil }
        let current = try await capture(target: target, fileSystem: fileSystem)
        var mappings = Set<DebuggerSourceMapping>()
        for library in info.libraries {
            try Task.checkCancellation()
            guard !library.identifier.isEmpty, !library.identifier.contains("/"),
                  library.identifier != ".", library.identifier != ".." else { return nil }
            let path = artifact.appending(components: library.identifier, fileName)
            guard let data = try await metadataData(at: path, enclosedBy: artifactRoot, fileSystem: fileSystem)
            else { return nil }
            let original = try JSONDecoder().decode(Self.self, from: data)
            guard original.version == currentVersion,
                  original.moduleName == current.moduleName,
                  original.debugPaths.keys.allSatisfy({ original.sources[$0] == current.sources[$0] }),
                  original.sourceRoot != .root,
                  Set(original.sourcePaths.keys) == Set(original.sources.keys),
                  Set(original.debugPaths.keys).isSubset(of: Set(original.sources.keys)),
                  original.sources.isEmpty || !original.debugPaths.isEmpty
            else { return nil }
            // Exact file mappings also cover declared headers/sources outside PROJECT_DIR, without
            // an absolute producer path shadowing a mapped path when LLDB reverses source breakpoints.
            for (relativePath, debugPath) in original.debugPaths {
                guard !debugPath.contains(where: \.isNewline) else { return nil }
                mappings.insert(DebuggerSourceMapping(
                    original: try AbsolutePath(validating: debugPath),
                    current: current.sourceRoot.appending(try RelativePath(validating: relativePath))
                ))
            }
        }
        return mappings.sorted { $0.original.pathString < $1.original.pathString }
    }

    private static func metadataData(
        at path: AbsolutePath,
        enclosedBy root: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> Data? {
        guard try await fileSystem.exists(path) else { return nil }
        let resolved = try await fileSystem.resolveSymbolicLink(path)
        guard resolved.pathString.hasPrefix(root.pathString + "/"),
              let file = try await fileSystem.fileMetadata(at: resolved), file.size <= Int64(maximumSize)
        else { return nil }
        let data = try await fileSystem.readFile(at: resolved)
        return data.count <= maximumSize ? data : nil
    }
}

private enum DebuggingMetadataError: LocalizedError {
    case ambiguousSource(String)
    case missingSources
    case excessiveSize

    var errorDescription: String? {
        switch self {
        case let .ambiguousSource(path):
            "Cannot unambiguously relocate the debug source \(path)."
        case .missingSources:
            "The cached product contains no debug information for its declared sources."
        case .excessiveSize:
            "The cached product's debugging source metadata exceeds the supported size."
        }
    }
}
