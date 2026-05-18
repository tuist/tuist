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
            }
        }
    }

    // MARK: - Fileprivate

    private func process(file: FileDescriptor) async throws {
        switch file.state {
        case .present:
            try await fileSystem.makeDirectory(at: file.path.parentDirectory)
            if let contents = file.contents {
                try contents.write(to: file.path.url)
            } else {
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
}

#if DEBUG
    final class MockSideEffectDescriptorExecutor: SideEffectDescriptorExecuting {
        var executeStub: (([SideEffectDescriptor]) throws -> Void)?
        func execute(sideEffects: [SideEffectDescriptor]) async throws {
            try executeStub?(sideEffects)
        }
    }
#endif
