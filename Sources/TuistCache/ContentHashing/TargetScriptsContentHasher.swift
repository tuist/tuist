import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public protocol TargetScriptsContentHashing {
    func hash(targetScripts: [TargetScript]) throws -> String
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
    public func hash(targetScripts: [TargetScript]) throws -> String {
        var stringsToHash: [String] = []
        for script in targetScripts {
            var pathsToHash: [AbsolutePath] = []
            script.path.map { pathsToHash.append($0) }
            let scriptPaths = script.inputPaths + script.inputFileListPaths + script.outputPaths + script.outputFileListPaths
            scriptPaths.forEach { path in
                if path.pathString.contains("$") {
                    stringsToHash.append(path.pathString)
                    logger
                        .notice(
                            "The path of the file \'\(path.url.lastPathComponent)\' is hashed, not the content. Because it has a build variable."
                        )
                } else {
                    pathsToHash.append(path)
                }
            }
            let fileHashes = try pathsToHash.map { try contentHasher.hash(path: $0) }
            stringsToHash.append(
                contentsOf: fileHashes +
                    [
                        script.name,
                        script.tool ?? "", // TODO: don't default to ""
                        script.order.rawValue,
                    ] +
                    script.arguments
            )
        }
        return try contentHasher.hash(stringsToHash)
    }
}
