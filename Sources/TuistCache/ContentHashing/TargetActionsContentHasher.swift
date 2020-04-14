import Foundation
import TuistCore

public protocol TargetActionsContentHashing {
    func hash(targetActions: [TargetAction]) throws -> String
}

public final class TargetActionsContentHasher: TargetActionsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    // MARK: - TargetActionsContentHasher

    /// Returns the hash that uniquely identifies an array of target actions
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the tool to execute, the order, the arguments and its name
    public func hash(targetActions: [TargetAction]) throws -> String {
        var stringsToHash: [String] = []
        for targetAction in targetActions {
            let pathsToHash = [targetAction.path ?? ""] + targetAction.inputPaths + targetAction.inputFileListPaths + targetAction.outputPaths + targetAction.outputFileListPaths
            let fileHashes = try pathsToHash.map { try contentHasher.hash(fileAtPath: $0) }
            stringsToHash.append(contentsOf: fileHashes +
                [targetAction.name,
                targetAction.tool ?? "",
                targetAction.order.rawValue] +
            targetAction.arguments)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
