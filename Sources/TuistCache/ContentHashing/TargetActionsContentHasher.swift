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

    /// Returns the hash that uniquely identify an array of target actions
    /// The hash takes into consideration the content of the script to execute, the input paths, the output paths, the outputFileListPaths, the name of the tool to execute, the order, the arguments and its name
    public func hash(targetActions: [TargetAction]) throws -> String {
        var stringsToHash: [String] = []
        for targetAction in targetActions {
            let contentHash = try contentHasher.hash(targetAction.path ?? "")
            let inputPaths = targetAction.inputPaths.map { $0.pathString }
            let inputFileListPaths = targetAction.inputFileListPaths.map { $0.pathString }
            let outputPaths = targetAction.outputPaths.map { $0.pathString }
            let outputFileListPaths = targetAction.outputFileListPaths.map { $0.pathString }
            stringsToHash.append(contentsOf:
                [contentHash,
                targetAction.name,
                targetAction.tool ?? "",
                targetAction.order.rawValue])
            stringsToHash.append(contentsOf:
                               targetAction.arguments +
                               inputPaths +
                               inputFileListPaths +
                               outputPaths +
                               outputFileListPaths)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
