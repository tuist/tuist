import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public protocol TargetScriptsContentHashing {
    func hash(targetScripts: [TargetScript], sourceRootPath: AbsolutePath) throws -> String
}

/// `TargetScriptsContentHasher`
/// is responsible for computing a unique hash that identifies a list of target scripts
public final class TargetScriptsContentHasher: TargetScriptsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - TargetScriptsContentHashing

    /// Returns the hash that uniquely identifies an array of target scripts
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the tool to execute, the order, the arguments and its name
    public func hash(targetScripts: [TargetScript], sourceRootPath: AbsolutePath) throws -> String {
        var stringsToHash: [String] = []
        for script in targetScripts {
            var pathsToHash: [AbsolutePath] = []
            script.path.map { pathsToHash.append($0) }

            var dynamicPaths = script.inputPaths + script.inputFileListPaths
            if let dependencyFile = script.dependencyFile {
                dynamicPaths += [dependencyFile]
            }

            dynamicPaths.forEach { path in
                if path.pathString.contains("$") {
                    stringsToHash.append(path.relative(to: sourceRootPath).pathString)
                    logger.notice(
                        "The path of the file \'\(path.url.lastPathComponent)\' is hashed, not the content. Because it has a build variable."
                    )
                } else {
                    pathsToHash.append(path)
                }
            }
            stringsToHash.append(contentsOf: try pathsToHash.map { try contentHasher.hash(path: $0) })
            stringsToHash.append(
                contentsOf: (script.outputPaths + script.outputFileListPaths).map { $0.relative(to: sourceRootPath).pathString }
            )

            stringsToHash.append(contentsOf: [
                script.name,
                script.tool ?? "",
                script.order.rawValue,
            ] + script.arguments)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
