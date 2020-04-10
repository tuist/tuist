import Foundation
import TuistCore
import TuistSupport

/// The protocol defines an interface for executing side effects.
public protocol SideEffectDescriptorExecuting: AnyObject {
    /// Executes the given side effects sequentially.
    /// - Parameter sideEffects: Side effects to be executed.
    func execute(sideEffects: [SideEffectDescriptor]) throws
}

public final class SideEffectDescriptorExecutor: SideEffectDescriptorExecuting {
    public init() {}

    // MARK: - SideEffectDescriptorExecuting

    public func execute(sideEffects: [SideEffectDescriptor]) throws {
        for sideEffect in sideEffects {
            switch sideEffect {
            case let .command(commandDescriptor):
                try perform(command: commandDescriptor)
            case let .file(fileDescriptor):
                try process(file: fileDescriptor)
            }
        }
    }

    // MARK: - Fileprivate

    private func process(file: FileDescriptor) throws {
        switch file.state {
        case .present:
            try FileHandler.shared.createFolder(file.path.parentDirectory)
            if let contents = file.contents {
                try contents.write(to: file.path.url)
            } else {
                try FileHandler.shared.touch(file.path)
            }
        case .absent:
            try FileHandler.shared.delete(file.path)
        }
    }

    private func perform(command: CommandDescriptor) throws {
        try System.shared.run(command.command)
    }
}
