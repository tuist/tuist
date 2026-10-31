import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
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
    private static let currentVersion = 2
    private static let maximumSize = 4 * 1024 * 1024

    public let version: Int
    public let moduleName: String
    public let sourceRoot: AbsolutePath
    public let sources: [String: String]
    public let sourcePaths: [String: String]
    public let debugPaths: [String: Set<String>]

    public static func capture(
        target: GraphTarget,
        fileSystem: FileSysteming = FileSystem(),
        validateGeneratedSources: Bool = false
    ) async throws -> Self {
        try await capture(
            target: target, declared: declaredSources(for: target), fileSystem: fileSystem,
            validateGeneratedSources: validateGeneratedSources
        )
    }

    private static func declaredSources(for target: GraphTarget) throws -> [String: SourceFile] {
        let filter = HashingFilesFilter()
        let folders = target.target.buildableFolders.flatMap(\.resolvedFiles).map(\.path).filter(filter.callAsFunction)
        let included = target.project.targets.values.filter { $0.name != target.target.name }
            .flatMap(\.buildableFolders).flatMap(\.exceptions)
            .filter { $0.target == target.target.name }.flatMap(\.included).filter(filter.callAsFunction)
        let headers = (target.target.headers?.public ?? []) + (target.target.headers?.private ?? []) +
            (target.target.headers?.project ?? [])
        var declared: [String: SourceFile] = [:]
        for source in target.target.sources + (folders + included + headers).map({ SourceFile(path: $0) }) {
            let relative = source.path.relative(to: target.project.sourceRootPath).pathString
            if let previous = declared[relative]?.contentHash {
                guard source.contentHash == nil || source.contentHash == previous else {
                    throw DebuggingMetadataError.ambiguousSource(relative)
                }
                continue
            }
            declared[relative] = source
        }
        return declared
    }

    private static func capture(
        target: GraphTarget,
        declared: [String: SourceFile],
        fileSystem: FileSysteming,
        validateGeneratedSources: Bool = false
    ) async throws -> Self {
        try Task.checkCancellation()
        let hasher = ContentHasher(fileSystem: fileSystem)
        let identities = try await declared.filter { $0.value.contentHashIsPlaceholder != true }
            .sorted(by: { $0.key < $1.key })
            .concurrentMap(maxConcurrentTasks: 8) { relative, source in
                try Task.checkCancellation()
                let checksum: String
                if let generated = source.contentHash, !validateGeneratedSources {
                    checksum = generated
                } else {
                    checksum = try await hasher.hash(path: source.path)
                }
                return (relative, checksum, try await canonicalSourcePath(source.path, fileSystem: fileSystem))
            }
        return Self(
            version: currentVersion, moduleName: target.target.productName, sourceRoot: target.project.sourceRootPath,
            sources: Dictionary(uniqueKeysWithValues: identities.map { ($0.0, $0.1) }),
            sourcePaths: Dictionary(uniqueKeysWithValues: identities.map { ($0.0, $0.2) }), debugPaths: [:]
        )
    }

    /// Uses paths actually present in DWARF. Multiple verified spellings of one file are not ambiguous.
    /// `linkedDebugSymbols` marks `debugSources` as read from a linked dSYM, which drops compile units without code.
    public func recording(
        debugSources: Set<String>,
        prefixMappings: [[String: String]] = [],
        linkedDebugSymbols: Bool = false
    ) throws -> Self {
        try recording(
            debugSources: debugSources, prefixMappings: prefixMappings, linkedDebugSymbols: linkedDebugSymbols,
            resolvedDebugSources: [:], symlinkedSources: []
        )
    }

    public func recording(
        debugSources: Set<String>,
        prefixMappings: [[String: String]] = [],
        linkedDebugSymbols: Bool = false,
        fileSystem: FileSysteming
    ) async throws -> Self {
        try Task.checkCancellation()
        let declaredPaths = Set(sourcePaths.values)
        var resolvedDebugSources: [String: Set<String>] = [:]
        for source in debugSources.sorted() {
            try Task.checkCancellation()
            guard let path = try? AbsolutePath(validating: source), try await fileSystem.exists(path) else { continue }
            let canonical = try await Self.canonicalSourcePath(path, fileSystem: fileSystem)
            guard declaredPaths.contains(canonical) else { continue }
            resolvedDebugSources[canonical, default: []].insert(source)
        }
        var symlinkedSources: Set<String> = []
        for spellings in Self.spellingsOfSharedFiles(sourcePaths) {
            for relative in spellings {
                try Task.checkCancellation()
                let path = sourceRoot.appending(try RelativePath(validating: relative))
                if try await fileSystem.exists(path), try await fileSystem.resolveSymbolicLink(path) != path {
                    symlinkedSources.insert(relative)
                }
            }
        }
        return try recording(
            debugSources: debugSources, prefixMappings: prefixMappings, linkedDebugSymbols: linkedDebugSymbols,
            resolvedDebugSources: resolvedDebugSources, symlinkedSources: symlinkedSources
        )
    }

    private func recording(
        debugSources: Set<String>,
        prefixMappings: [[String: String]],
        linkedDebugSymbols: Bool,
        resolvedDebugSources: [String: Set<String>],
        symlinkedSources: Set<String>
    ) throws -> Self {
        var candidatesBySource: [String: Set<String>] = [:]
        for relative in sources.keys.sorted() {
            let original = sourceRoot.appending(try RelativePath(validating: relative)).pathString
            var candidates: Set<String> = [original]
            if let canonical = sourcePaths[relative] {
                candidates.insert(canonical)
                candidates.formUnion(resolvedDebugSources[canonical] ?? [])
            }
            for mappings in prefixMappings {
                for (alias, root) in mappings {
                    guard let root = try? AbsolutePath(validating: root).pathString else {
                        throw DebuggingMetadataError.unavailableSymbols("Invalid compiler prefix mapping: \(root)")
                    }
                    let prefix = root == "/" ? root : root + "/"
                    for source in [original, sourcePaths[relative]].compactMap({ $0 }) where source.hasPrefix(prefix) {
                        candidates.insert((alias.hasSuffix("/") ? alias : alias + "/") + source.dropFirst(prefix.count))
                    }
                }
            }
            candidatesBySource[relative] = candidates
        }
        // Spellings of one file relocate to the same bytes; the one that is not a symlink owns them.
        for spellings in Self.spellingsOfSharedFiles(sourcePaths) {
            let owner = spellings.first { !symlinkedSources.contains($0) } ?? spellings[0]
            for spelling in spellings where spelling != owner {
                candidatesBySource[owner, default: []].formUnion(candidatesBySource.removeValue(forKey: spelling) ?? [])
            }
        }
        var paths: [String: Set<String>] = [:]
        var owners: [String: String] = [:]
        for (relative, candidates) in candidatesBySource.sorted(by: { $0.key < $1.key }) {
            let matches = candidates.intersection(debugSources)
            for match in matches {
                guard owners[match] == nil else { throw DebuggingMetadataError.ambiguousSource(match) }
                owners[match] = relative
            }
            if !matches.isEmpty { paths[relative] = matches }
        }
        if !sources.isEmpty, paths.isEmpty {
            let names = Set((Array(sources.keys) + Array(sourcePaths.values)).map(Self.lowercasedFileName))
            guard linkedDebugSymbols, !debugSources.contains(where: { names.contains(Self.lowercasedFileName($0)) }) else {
                throw DebuggingMetadataError.missingSources
            }
        }
        let metadata = Self(
            version: version, moduleName: moduleName, sourceRoot: sourceRoot,
            sources: sources, sourcePaths: sourcePaths, debugPaths: paths
        )
        guard try JSONEncoder().encode(metadata).count <= Self.maximumSize else { throw DebuggingMetadataError.excessiveSize }
        return metadata
    }

    /// Missing, incompatible or ambiguous metadata retains sources. Only observed declared files need content reads.
    /// Metadata that observed none of the declared sources returns no mappings: nothing is relocated.
    public static func sourceMappings(
        at artifact: AbsolutePath,
        for target: GraphTarget,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> [DebuggerSourceMapping]? {
        try Task.checkCancellation()
        let artifactRoot = try AbsolutePath(validating: await canonicalSourcePath(artifact, fileSystem: fileSystem))
        guard let infoData = try await metadataData(
            at: artifact.appending(component: "Info.plist"), enclosedBy: artifactRoot, fileSystem: fileSystem
        ) else { return nil }
        let info = try PropertyListDecoder().decode(XCFrameworkInfoPlist.self, from: infoData)
        guard !info.libraries.isEmpty else { return nil }
        let declared = try declaredSources(for: target)
        guard !declared.values.contains(where: { $0.contentHashIsPlaceholder == true }) else { return nil }
        var slices: [Self] = []
        for library in info.libraries {
            try Task.checkCancellation()
            guard !library.identifier.isEmpty, !library.identifier.contains("/"),
                  library.identifier != ".", library.identifier != ".." else { return nil }
            guard let data = try await metadataData(
                at: artifact.appending(components: library.identifier, fileName), enclosedBy: artifactRoot, fileSystem: fileSystem
            ) else { return nil }
            let original = try JSONDecoder().decode(Self.self, from: data)
            guard original.version == currentVersion, original.moduleName == target.target.productName,
                  original.sourceRoot != .root,
                  Set(original.sourcePaths.keys) == Set(original.sources.keys),
                  Set(original.debugPaths.keys).isSubset(of: Set(original.sources.keys)),
                  Set(original.debugPaths.keys).isSubset(of: Set(declared.keys)),
                  original.debugPaths.values.allSatisfy({ !$0.isEmpty }),
                  !original.debugPaths.isEmpty || Set(original.sources.keys) == Set(declared.keys)
            else { return nil }
            slices.append(original)
        }
        let observed = Set(slices.flatMap(\.debugPaths.keys))
        let current = try await capture(
            target: target, declared: declared.filter { observed.contains($0.key) }, fileSystem: fileSystem
        )
        var destinations: [AbsolutePath: AbsolutePath] = [:]
        for original in slices {
            for (relative, debugPaths) in original.debugPaths {
                guard original.sources[relative] == current.sources[relative] else { return nil }
                let destination = target.project.sourceRootPath.appending(try RelativePath(validating: relative))
                for debugPath in debugPaths {
                    guard !debugPath.contains(where: \.isNewline) else { return nil }
                    let path = try AbsolutePath(validating: debugPath)
                    guard destinations[path] == nil || destinations[path] == destination else { return nil }
                    destinations[path] = destination
                }
            }
        }
        return destinations.map { DebuggerSourceMapping(original: $0.key, current: $0.value) }
            .sorted { $0.original.pathString < $1.original.pathString }
    }

    /// Declared relative paths that canonicalize to one file, sorted, for each such file.
    private static func spellingsOfSharedFiles(_ sourcePaths: [String: String]) -> [[String]] {
        Dictionary(grouping: sourcePaths, by: \.value).values
            .filter { $0.count > 1 }.map { $0.map(\.key).sorted() }.sorted { $0[0] < $1[0] }
    }

    private static func lowercasedFileName(_ path: String) -> String {
        (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
    }

    private static func canonicalSourcePath(_ path: AbsolutePath, fileSystem: FileSysteming) async throws -> String {
        var ancestor = path
        var missing: [String] = []
        while try await !fileSystem.exists(ancestor) {
            try Task.checkCancellation()
            guard ancestor != .root else { throw DebuggingMetadataError.missingSources }
            missing.append(ancestor.basename)
            ancestor = ancestor.parentDirectory
        }
        // FileSystem resolves only the leaf. Resolve parent links even for not-yet-written generated sources.
        let resolved = try await fileSystem.resolveSymbolicLink(ancestor).url.resolvingSymlinksInPath()
        return missing.reversed().reduce(resolved) { $0.appendingPathComponent($1) }.path
    }

    private static func metadataData(
        at path: AbsolutePath,
        enclosedBy root: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> Data? {
        guard try await fileSystem.exists(path) else { return nil }
        let resolved = try AbsolutePath(validating: await canonicalSourcePath(path, fileSystem: fileSystem))
        guard resolved.pathString.hasPrefix(root.pathString + "/"),
              let file = try await fileSystem.fileMetadata(at: resolved), file.size <= Int64(maximumSize)
        else { return nil }
        let data = try await fileSystem.readFile(at: resolved)
        return data.count <= maximumSize ? data : nil
    }
}

public enum DebuggingMetadataError: LocalizedError {
    case ambiguousSource(String)
    case missingSources
    case excessiveSize
    case unavailableSymbols(String)

    public var errorDescription: String? {
        switch self {
        case let .ambiguousSource(path):
            "Cannot unambiguously relocate the debug source \(path)."
        case .missingSources:
            "The cached product contains no debug information for its declared sources."
        case .excessiveSize:
            "The cached product's debugging source metadata exceeds the supported size."
        case let .unavailableSymbols(reason):
            "The cached product's debugging information is unavailable: \(reason)"
        }
    }
}
