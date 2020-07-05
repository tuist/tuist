import Foundation
import TSCBasic
import TuistCore

public protocol TargetActionsContentHashing {
    func hash(targetActions: [TargetAction]) throws -> String
}

/// `TargetActionsContentHasher`
/// is responsible for computing a unique hash that identifies a list of target actions
public final class TargetActionsContentHasher: TargetActionsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - TargetActionsContentHasher

    /// Returns the hash that uniquely identifies an array of target actions
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the tool to execute, the order, the arguments and its name
    public func hash(targetActions: [TargetAction]) throws -> String {
        var stringsToHash: [String] = []
        for targetAction in targetActions {
            var pathsToHash: [AbsolutePath] = [targetAction.path ?? ""]
            pathsToHash.append(contentsOf: targetAction.inputPaths)
            pathsToHash.append(contentsOf: targetAction.inputFileListPaths)
            pathsToHash.append(contentsOf: targetAction.outputPaths)
            pathsToHash.append(contentsOf: targetAction.outputFileListPaths)
            let fileHashes = try pathsToHash.map { try contentHasher.hash(fileAtPath: $0) }
            stringsToHash.append(contentsOf: fileHashes +
                [targetAction.name,
                 targetAction.tool ?? "", // TODO: don't default to ""
                 targetAction.order.rawValue] +
                targetAction.arguments)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
