import Foundation
import Path
import TuistCore
import XcodeGraph

public protocol TargetScriptsContentHashing {
    func hash(identifier: String, targetScripts: [TargetScript], sourceRootPath: AbsolutePath) throws -> MerkleNode
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
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the
    /// tool to execute, the order, the arguments and its name
    public func hash(identifier: String, targetScripts: [TargetScript], sourceRootPath: AbsolutePath) throws -> MerkleNode {
        var children = try targetScripts.map { targetScript in
            var targetScriptChildren = [
                MerkleNode(hash: try contentHasher.hash(targetScript.name), identifier: "name"),
                MerkleNode(hash: try contentHasher.hash(targetScript.order.rawValue), identifier: "order"),
                MerkleNode(hash: try contentHasher.hash(targetScript.arguments), identifier: "arguments"),
                MerkleNode(hash: try contentHasher.hash(targetScript.showEnvVarsInLog), identifier: "showEnvVarsInLog"),
                MerkleNode(
                    hash: try contentHasher.hash(targetScript.runForInstallBuildsOnly),
                    identifier: "runForInstallBuildsOnly"
                ),
                MerkleNode(hash: try contentHasher.hash(targetScript.shellPath), identifier: "shellPath"),
            ]

            switch targetScript.script {
            case let .embedded(embeddedScript):
                targetScriptChildren.append(MerkleNode(
                    hash: try contentHasher.hash(embeddedScript),
                    identifier: "embeddedScript"
                ))
            case let .scriptPath(scriptPath, arguments):
                targetScriptChildren.append(try hash(path: scriptPath, sourceRootPath: sourceRootPath))
                targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(arguments), identifier: "arguments"))
            case let .tool(tool, arguments):
                targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(tool), identifier: "tool"))
                targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(arguments), identifier: "arguments"))
            }

            if let basedOnDependencyAnalysis = targetScript.basedOnDependencyAnalysis {
                targetScriptChildren.append(MerkleNode(
                    hash: try contentHasher.hash(basedOnDependencyAnalysis),
                    identifier: "basedOnDependencyAnalysis"
                ))
            }

            if let embeddedScript = targetScript.embeddedScript {
                targetScriptChildren.append(MerkleNode(
                    hash: try contentHasher.hash(embeddedScript),
                    identifier: "embeddedScript"
                ))
            }

            if let tool = targetScript.tool {
                targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(tool), identifier: "tool"))
            }

            if let path = targetScript.path {
                targetScriptChildren.append(try hash(path: path, sourceRootPath: sourceRootPath))
            }

            if let dependencyFile = targetScript.dependencyFile {
                targetScriptChildren.append(try hash(path: dependencyFile, sourceRootPath: sourceRootPath))
            }

            let inputPathsChildren = try targetScript.inputPaths
                .compactMap { try? AbsolutePath(validating: $0) }
                .map { try hash(path: $0, sourceRootPath: sourceRootPath) }
            targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(inputPathsChildren), identifier: "inputPaths"))

            let inputFileListPathsChildren = try targetScript.inputFileListPaths.map { try hash(
                path: $0,
                sourceRootPath: sourceRootPath
            ) }
            targetScriptChildren.append(MerkleNode(
                hash: try contentHasher.hash(inputFileListPathsChildren),
                identifier: "inputFileListPaths"
            ))

            let outputPathsChildren = try targetScript.outputPaths
                .compactMap { try? AbsolutePath(validating: $0) }
                .map { $0.relative(to: sourceRootPath).pathString }
                .map { try contentHasher.hash($0) }
            targetScriptChildren.append(MerkleNode(hash: try contentHasher.hash(outputPathsChildren), identifier: "outputPaths"))

            let outputFileListPathsChildren = try targetScript.outputFileListPaths
                .map { $0.relative(to: sourceRootPath).pathString }
                .map { try contentHasher.hash($0) }
            targetScriptChildren.append(MerkleNode(
                hash: try contentHasher.hash(outputFileListPathsChildren),
                identifier: "outputFileListPaths"
            ))

            return MerkleNode(
                hash: try contentHasher.hash(targetScriptChildren),
                identifier: targetScript.name,
                children: targetScriptChildren
            )
        }

        return MerkleNode(hash: try contentHasher.hash(children), identifier: identifier, children: children)
    }

    private func hash(path: AbsolutePath, sourceRootPath: AbsolutePath) throws -> MerkleNode {
        let identifier = path.relative(to: sourceRootPath).pathString
        if path.pathString.contains("$") {
            return MerkleNode(hash: try contentHasher.hash(identifier), identifier: "content")
        } else {
            return MerkleNode(hash: try contentHasher.hash(path: path), identifier: identifier)
        }
    }
}
