import Command
import FileSystem
import Foundation
import TuistCore
import TuistLogging
import TuistSupport

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
            let generatedFiles = try await fileSystem.glob(directory: directory, include: descriptor.include).collect()
            for generatedFile in generatedFiles.sorted(by: { $0.pathString < $1.pathString })
                where !activeFiles.contains(generatedFile)
            {
                try await fileSystem.remove(generatedFile)
            }
        }
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
