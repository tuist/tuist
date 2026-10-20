import FileSystem
import Foundation
import Path
import TuistCore
import TuistLogging
import TuistProcess
import TuistSupport

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// The protocol defines an interface for executing side effects.
public protocol SideEffectDescriptorExecuting {
    /// Executes the given side effects in order.
    ///
    /// Consecutive file and symbolic link side effects that don't touch the same entries on disk, including
    /// through symbolic links, may run concurrently. Every other side effect waits for the ones before it and
    /// blocks the ones after it.
    /// - Parameter sideEffects: Side effects to be executed.
    func execute(sideEffects: [SideEffectDescriptor]) async throws
}

public struct SideEffectDescriptorExecutor: SideEffectDescriptorExecuting {
    private let fileSystem: FileSystem
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSystem = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    // MARK: - SideEffectDescriptorExecuting

    public func execute(sideEffects: [SideEffectDescriptor]) async throws {
        var batch = IndependentSideEffects()
        for sideEffect in sideEffects {
            Logger.current.debug("Side effect: \(sideEffect)")
            switch sideEffect {
            case let .file(fileDescriptor):
                try await enqueue(.file(fileDescriptor), in: &batch)
            case let .symbolicLink(symbolicLinkDescriptor):
                try await enqueue(.symbolicLink(symbolicLinkDescriptor), in: &batch)
            case let .command(commandDescriptor):
                try await execute(batch.removeAll())
                try await perform(command: commandDescriptor)
            case let .directory(directoryDescriptor):
                try await execute(batch.removeAll())
                try await process(directory: directoryDescriptor)
            case let .testPlan(testPlanDescriptor):
                try await execute(batch.removeAll())
                try await process(testPlan: testPlanDescriptor)
            case let .generatedFilesCleanup(descriptor):
                try await execute(batch.removeAll())
                try await process(generatedFilesCleanup: descriptor)
            }
        }
        try await execute(batch)
    }

    // MARK: - Fileprivate

    private func enqueue(
        _ sideEffect: IndependentSideEffects.SideEffect,
        in batch: inout IndependentSideEffects
    ) async throws {
        guard try !batch.insert(sideEffect) else { return }
        try await execute(batch.removeAll())
        try batch.insert(sideEffect)
    }

    private func execute(_ batch: IndependentSideEffects) async throws {
        for directory in batch.parentDirectories.sorted(by: { $0.pathString < $1.pathString }) {
            try await fileSystem.makeDirectory(at: directory)
        }
        _ = try await batch.sideEffects.concurrentMap(
            maxConcurrentTasks: ProcessInfo.processInfo.activeProcessorCount
        ) { sideEffect in
            switch sideEffect {
            case let .file(fileDescriptor):
                try await process(file: fileDescriptor)
            case let .symbolicLink(symbolicLinkDescriptor):
                try await process(symbolicLink: symbolicLinkDescriptor)
            }
        }
    }

    /// Expects the parent directory of a present file to exist.
    private func process(file: FileDescriptor) async throws {
        switch file.state {
        case .present:
            if let contents = file.contents {
                if try await fileSystem.exists(file.path),
                   try await fileSystem.readFile(at: file.path) == contents
                {
                    return
                }
                try contents.write(to: file.path.url)
            } else if try await !fileSystem.exists(file.path) {
                try await fileSystem.touch(file.path)
            }
        case .absent:
            try await fileSystem.remove(file.path)
        }
    }

    private func process(directory: DirectoryDescriptor) async throws {
        switch directory.state {
        case .present:
            if try await !fileSystem.exists(directory.path) {
                try await fileSystem.makeDirectory(at: directory.path)
            }
        case .absent:
            if try await fileSystem.exists(directory.path) {
                try await fileSystem.remove(directory.path)
            }
        }
    }

    /// Expects the parent directory of a present symbolic link to exist.
    private func process(symbolicLink: SymbolicLinkDescriptor) async throws {
        switch symbolicLink.state {
        case .present:
            switch try entryType(at: symbolicLink.path) {
            case nil:
                break
            case .symbolicLink:
                if try symbolicLinkDestination(at: symbolicLink.path) == symbolicLink.destination {
                    return
                }
                try await removeDirectoryEntry(symbolicLink.path)
            case .directory, .other:
                try await fileSystem.remove(symbolicLink.path)
            }
            try await fileSystem.createSymbolicLink(from: symbolicLink.path, to: symbolicLink.destination)
        case .absent:
            try await removeExistingEntry(symbolicLink.path)
        }
    }

    /// Removes the entry at the path without following it, so a symbolic link is removed even when its
    /// destination no longer exists.
    private func removeExistingEntry(_ path: AbsolutePath) async throws {
        switch try entryType(at: path) {
        case nil:
            return
        case .directory:
            try await fileSystem.remove(path)
        case .symbolicLink, .other:
            try await removeDirectoryEntry(path)
        }
    }

    private func removeDirectoryEntry(_ path: AbsolutePath) async throws {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            guard unlink(path.pathString) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        #else
            try await fileSystem.remove(path)
        #endif
    }

    private func perform(command: CommandDescriptor) async throws {
        try await commandRunner.runAndWait(arguments: command.command)
    }

    private func process(testPlan: TestPlanDescriptor) async throws {
        let parent = testPlan.path.parentDirectory
        if try await !fileSystem.exists(parent) {
            try await fileSystem.makeDirectory(at: parent)
        }
        let data = try testPlan.encode()
        try data.write(to: testPlan.path.url)
    }

    private func process(generatedFilesCleanup descriptor: GeneratedFilesCleanupDescriptor) async throws {
        let patterns = try descriptor.include.map { pattern in
            try pattern.split(separator: "/").map { try PathPatternComponent(String($0)) }
        }
        for directory in descriptor.directories.sorted(by: { $0.pathString < $1.pathString }) {
            guard try entryType(at: directory) == .directory else { continue }

            let pathKey = try filePathKey(in: directory)
            let activeFileKeys = Set((descriptor.activeFilesByDirectory[directory] ?? []).map(pathKey))
            var generatedFiles: Set<AbsolutePath> = []
            for pattern in patterns {
                generatedFiles.formUnion(try await directoryEntries(matching: pattern, in: directory))
            }
            for generatedFile in generatedFiles.sorted(by: { $0.pathString < $1.pathString })
                where !activeFileKeys.contains(pathKey(generatedFile))
            {
                guard try !hasSymbolicLinkAncestor(generatedFile, under: directory) else { continue }
                try await removeExistingEntry(generatedFile)
            }
        }
    }

    private func filePathKey(in directory: AbsolutePath) throws -> (AbsolutePath) -> String {
        // Case-only writes retain the original directory-entry spelling on case-insensitive volumes.
        let values = try directory.url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        let isCaseSensitive = values.volumeSupportsCaseSensitiveNames ?? true
        return { path in
            isCaseSensitive ? path.pathString : path.pathString.lowercased()
        }
    }

    /// Expects `directory` to be a directory rather than a symbolic link to one.
    private func directoryEntries(
        matching components: [PathPatternComponent],
        in directory: AbsolutePath
    ) async throws -> Set<AbsolutePath> {
        guard let component = components.first else { return [] }

        switch component {
        case .anyDirectories:
            var matchedEntries = try await directoryEntries(matching: Array(components.dropFirst()), in: directory)
            for entry in try await fileSystem.contentsOfDirectory(directory) {
                guard try entryType(at: entry) == .directory else { continue }
                matchedEntries.formUnion(try await directoryEntries(matching: components, in: entry))
            }
            return matchedEntries
        case let .name(name):
            if components.count == 1 {
                return Set(try await fileSystem.contentsOfDirectory(directory).filter { name.matches($0.basename) })
            }
            let nextDirectories: [AbsolutePath]
            if case let .literal(literal) = name {
                nextDirectories = [directory.appending(component: literal)]
            } else {
                nextDirectories = try await fileSystem.contentsOfDirectory(directory).filter { name.matches($0.basename) }
            }

            let nextComponents = Array(components.dropFirst())
            var matchedEntries: Set<AbsolutePath> = []
            for nextDirectory in nextDirectories {
                guard try entryType(at: nextDirectory) == .directory else { continue }
                matchedEntries.formUnion(try await directoryEntries(matching: nextComponents, in: nextDirectory))
            }
            return matchedEntries
        }
    }

    private func hasSymbolicLinkAncestor(_ path: AbsolutePath, under directory: AbsolutePath) throws -> Bool {
        guard path.isDescendantOfOrEqual(to: directory) else { return false }

        var ancestor = path.parentDirectory
        while ancestor != directory, ancestor.isDescendantOfOrEqual(to: directory) {
            if try entryType(at: ancestor) == .symbolicLink {
                return true
            }
            ancestor = ancestor.parentDirectory
        }
        return false
    }
}

private enum EntryType {
    case directory
    case symbolicLink
    case other
}

/// The type of the entry at the path, without following a symbolic link, or `nil` when there's none.
private func entryType(at path: AbsolutePath) throws -> EntryType? {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        var status = stat()
        guard lstat(path.pathString, &status) == 0 else {
            if errno == ENOENT || errno == ENOTDIR { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        switch Int(status.st_mode) & Int(S_IFMT) {
        case Int(S_IFDIR): return .directory
        case Int(S_IFLNK): return .symbolicLink
        default: return .other
        }
    #else
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.pathString) else { return nil }
        switch attributes[.type] as? FileAttributeType {
        case .typeDirectory: return .directory
        case .typeSymbolicLink: return .symbolicLink
        default: return .other
        }
    #endif
}

private func symbolicLinkDestination(at path: AbsolutePath) throws -> AbsolutePath {
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path.pathString)
    return try AbsolutePath(validating: destination, relativeTo: path.parentDirectory)
}

/// A component of a `GeneratedFilesCleanupDescriptor` include pattern, compiled once per cleanup rather than
/// once per directory entry it's matched against.
private enum PathPatternComponent {
    enum Name {
        case literal(String)
        case glob(NSRegularExpression)

        func matches(_ value: String) -> Bool {
            switch self {
            case let .literal(literal):
                return value == literal
            case let .glob(expression):
                return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            }
        }
    }

    case anyDirectories
    case name(Name)

    init(_ component: String) throws {
        if component == "**" {
            self = .anyDirectories
        } else if component.isGlobComponent {
            let pattern = NSRegularExpression.escapedPattern(for: component)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            self = .name(.glob(try NSRegularExpression(pattern: "^\(pattern)$")))
        } else {
            self = .name(.literal(component))
        }
    }
}

/// Consecutive file and symbolic link side effects that can run in any order.
///
/// Paths are compared where they physically live, so an entry reached through a symbolic link keeps its order
/// relative to the same entry reached another way. A side effect joins the batch only when it modifies nothing that
/// a batched side effect modifies, lives under, or follows as a symbolic link, and when nothing it lives under or
/// follows is modified by a batched side effect. Paths are compared case-insensitively so two spellings of the same
/// entry on a case-insensitive volume keep their order.
private struct IndependentSideEffects {
    enum SideEffect: Sendable {
        case file(FileDescriptor)
        case symbolicLink(SymbolicLinkDescriptor)

        var path: AbsolutePath {
            switch self {
            case let .file(descriptor): descriptor.path
            case let .symbolicLink(descriptor): descriptor.path
            }
        }

        var isPresent: Bool {
            switch self {
            case let .file(descriptor): descriptor.state == .present
            case let .symbolicLink(descriptor): descriptor.state == .present
            }
        }
    }

    private(set) var sideEffects: [SideEffect] = []
    /// The parent directories of the present files and symbolic links, created before the batch runs.
    private(set) var parentDirectories: Set<AbsolutePath> = []
    /// The entries the batched side effects modify.
    private var modifiedPaths: Set<String> = []
    /// The entries the batched side effects modify or follow as symbolic links, and every directory above them.
    private var observedPaths: Set<String> = []
    /// Only valid while the batch is being assembled: running it changes what's on disk.
    private var resolver = PhysicalPathResolver()

    /// Adds the side effect to the batch unless it can't run concurrently with the ones already in it.
    @discardableResult
    mutating func insert(_ sideEffect: SideEffect) throws -> Bool {
        let (modified, followedLinks) = try footprint(of: sideEffect)
        guard !modified.contains(where: { observedPaths.contains(Self.key($0)) }) else { return false }
        for path in modified + followedLinks {
            guard !isModified(path) else { return false }
        }

        modifiedPaths.formUnion(modified.map(Self.key))
        for path in modified + followedLinks {
            observe(path)
        }
        if sideEffect.isPresent {
            parentDirectories.insert(sideEffect.path.parentDirectory)
        }
        sideEffects.append(sideEffect)
        return true
    }

    /// Empties the batch, returning the side effects it held.
    mutating func removeAll() -> IndependentSideEffects {
        defer { self = IndependentSideEffects() }
        return self
    }

    private mutating func footprint(
        of sideEffect: SideEffect
    ) throws -> (modified: [AbsolutePath], followedLinks: [AbsolutePath]) {
        let parent = try resolver.resolve(sideEffect.path.parentDirectory)
        let entry = parent.path.appending(component: sideEffect.path.basename)
        switch sideEffect {
        case let .file(descriptor) where descriptor.state == .present:
            // Writing a file writes through a symbolic link at its path.
            let destination = try resolver.resolve(descriptor.path)
            return ([entry, destination.path], destination.followedLinks)
        case .file, .symbolicLink:
            return ([entry], parent.followedLinks)
        }
    }

    /// Whether a batched side effect modifies the path or a directory above it.
    private func isModified(_ path: AbsolutePath) -> Bool {
        var ancestor = path
        while true {
            let key = Self.key(ancestor)
            if modifiedPaths.contains(key) { return true }
            // An observed path that isn't modified was checked when it was observed, and nothing added since
            // modifies it or a directory above it.
            if observedPaths.contains(key) || ancestor.isRoot { return false }
            ancestor = ancestor.parentDirectory
        }
    }

    private mutating func observe(_ path: AbsolutePath) {
        var ancestor = path
        while observedPaths.insert(Self.key(ancestor)).inserted, !ancestor.isRoot {
            ancestor = ancestor.parentDirectory
        }
    }

    private static func key(_ path: AbsolutePath) -> String {
        path.pathString.lowercased()
    }
}

/// Resolves paths to where they physically live, recording the symbolic links followed to get there. A path that
/// doesn't exist yet resolves to where it would be created.
private struct PhysicalPathResolver {
    struct Resolution {
        let path: AbsolutePath
        let followedLinks: [AbsolutePath]
        let exists: Bool
    }

    private static let maximumFollowedLinks = 32
    private var resolutions: [AbsolutePath: Resolution] = [:]

    mutating func resolve(_ path: AbsolutePath) throws -> Resolution {
        try resolve(path, followedLinkCount: 0)
    }

    private mutating func resolve(_ path: AbsolutePath, followedLinkCount: Int) throws -> Resolution {
        if let resolution = resolutions[path] { return resolution }
        guard !path.isRoot else { return Resolution(path: path, followedLinks: [], exists: true) }

        let parent = try resolve(path.parentDirectory, followedLinkCount: followedLinkCount)
        let candidate = parent.path.appending(component: path.basename)
        let type: EntryType? = if parent.exists { try entryType(at: candidate) } else { nil }
        let resolution: Resolution
        switch type {
        case nil:
            resolution = Resolution(path: candidate, followedLinks: parent.followedLinks, exists: false)
        case .directory, .other:
            resolution = Resolution(path: candidate, followedLinks: parent.followedLinks, exists: true)
        case .symbolicLink:
            guard followedLinkCount < Self.maximumFollowedLinks else { throw POSIXError(.ELOOP) }
            let destination = try resolve(symbolicLinkDestination(at: candidate), followedLinkCount: followedLinkCount + 1)
            resolution = Resolution(
                path: destination.path,
                followedLinks: parent.followedLinks + [candidate] + destination.followedLinks,
                exists: destination.exists
            )
        }
        resolutions[path] = resolution
        return resolution
    }
}

#if DEBUG
    final class MockSideEffectDescriptorExecutor: SideEffectDescriptorExecuting {
        var executeStub: (([SideEffectDescriptor]) throws -> Void)?
        func execute(sideEffects: [SideEffectDescriptor]) async throws {
            try executeStub?(sideEffects)
        }
    }
#endif
