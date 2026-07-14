import Command
import FileSystem
import Foundation
import Path
import TuistCore
import TuistLogging
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
    /// Executes the given side effects sequentially.
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
        for sideEffect in sideEffects {
            Logger.current.debug("Side effect: \(sideEffect)")
            switch sideEffect {
            case let .command(commandDescriptor):
                try await perform(command: commandDescriptor)
            case let .file(fileDescriptor):
                try await process(file: fileDescriptor)
            case let .directory(directoryDescriptor):
                try await process(directory: directoryDescriptor)
            case let .symbolicLink(symbolicLinkDescriptor):
                try await process(symbolicLink: symbolicLinkDescriptor)
            case let .testPlan(testPlanDescriptor):
                try await process(testPlan: testPlanDescriptor)
            case let .generatedFilesCleanup(descriptor):
                try await process(generatedFilesCleanup: descriptor)
            }
        }
    }

    // MARK: - Fileprivate

    private func process(file: FileDescriptor) async throws {
        switch file.state {
        case .present:
            try await fileSystem.makeDirectory(at: file.path.parentDirectory)
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

    private func process(symbolicLink: SymbolicLinkDescriptor) async throws {
        switch symbolicLink.state {
        case .present:
            try await fileSystem.makeDirectory(at: symbolicLink.path.parentDirectory)
            if let destination = try? await fileSystem.resolveSymbolicLink(symbolicLink.path) {
                if destination == symbolicLink.destination {
                    return
                }
                try await removeExistingEntry(symbolicLink.path)
            } else {
                try await removeExistingEntry(symbolicLink.path)
            }
            try await fileSystem.createSymbolicLink(from: symbolicLink.path, to: symbolicLink.destination)
        case .absent:
            try await removeExistingEntry(symbolicLink.path)
        }
    }

    private func removeExistingEntry(_ path: AbsolutePath) async throws {
        if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        } else if try await directoryContains(path) {
            try await removeDirectoryEntry(path)
        }
    }

    private func directoryContains(_ path: AbsolutePath) async throws -> Bool {
        guard try await fileSystem.exists(path.parentDirectory, isDirectory: true) else { return false }
        return try await fileSystem.contentsOfDirectory(path.parentDirectory).contains(path)
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
        for directory in descriptor.directories.sorted(by: { $0.pathString < $1.pathString }) {
            guard try await fileSystem.exists(directory, isDirectory: true) else { continue }

            let activeFiles = descriptor.activeFilesByDirectory[directory] ?? []
            let generatedFiles = try await generatedFiles(matching: descriptor, in: directory)
            for generatedFile in generatedFiles.sorted(by: { $0.pathString < $1.pathString })
                where !activeFiles.contains(generatedFile)
            {
                guard try await !hasSymbolicLinkAncestor(generatedFile, under: directory) else { continue }
                try await removeExistingEntry(generatedFile)
            }
        }
    }

    private func generatedFiles(
        matching descriptor: GeneratedFilesCleanupDescriptor,
        in directory: AbsolutePath
    ) async throws -> Set<AbsolutePath> {
        var generatedFiles: Set<AbsolutePath> = []
        for pattern in descriptor.include {
            let components = pattern.split(separator: "/").map(String.init)
            generatedFiles.formUnion(try await directoryEntries(matching: components, in: directory))
        }
        return generatedFiles
    }

    private func directoryEntries(matching components: [String], in directory: AbsolutePath) async throws -> Set<AbsolutePath> {
        guard let component = components.first else { return [] }
        guard try await fileSystem.exists(directory, isDirectory: true) else { return [] }

        if component == "**" {
            var matchedEntries = try await directoryEntries(matching: Array(components.dropFirst()), in: directory)
            for entry in try await fileSystem.contentsOfDirectory(directory) {
                guard try await fileSystem.exists(entry, isDirectory: true),
                      try await !isSymbolicLink(entry)
                else { continue }
                matchedEntries.formUnion(try await directoryEntries(matching: components, in: entry))
            }
            return matchedEntries
        }

        if components.count == 1 {
            return Set(
                try await fileSystem.contentsOfDirectory(directory)
                    .filter { matches($0.basename, pattern: component) }
            )
        }

        let nextComponents = Array(components.dropFirst())
        let nextDirectories: [AbsolutePath]
        if component.isGlobComponent {
            nextDirectories = try await fileSystem.contentsOfDirectory(directory)
                .filter { matches($0.basename, pattern: component) }
        } else {
            nextDirectories = [directory.appending(component: component)]
        }

        var matchedEntries: Set<AbsolutePath> = []
        for nextDirectory in nextDirectories {
            guard try await fileSystem.exists(nextDirectory, isDirectory: true),
                  try await !isSymbolicLink(nextDirectory)
            else { continue }
            matchedEntries.formUnion(try await directoryEntries(matching: nextComponents, in: nextDirectory))
        }
        return matchedEntries
    }

    private func matches(_ value: String, pattern: String) -> Bool {
        guard pattern.isGlobComponent else { return value == pattern }
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escapedPattern)$", options: .regularExpression) != nil
    }

    private func isSymbolicLink(_ path: AbsolutePath) async throws -> Bool {
        guard let destination = try? await fileSystem.resolveSymbolicLink(path) else { return false }
        return destination != path
    }

    private func hasSymbolicLinkAncestor(_ path: AbsolutePath, under directory: AbsolutePath) async throws -> Bool {
        guard path.isDescendantOfOrEqual(to: directory) else { return false }

        var ancestor = path.parentDirectory
        while ancestor != directory, ancestor.isDescendantOfOrEqual(to: directory) {
            if try await isSymbolicLink(ancestor) {
                return true
            }
            ancestor = ancestor.parentDirectory
        }
        return false
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
