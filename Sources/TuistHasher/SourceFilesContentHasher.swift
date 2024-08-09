import Foundation
import TuistCore
import XcodeGraph

public protocol SourceFilesContentHashing {
    func hash(identifier: String, sources: [SourceFile]) throws -> MerkelNode
}

/// `SourceFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of source files, considering their content
public final class SourceFilesContentHasher: SourceFilesContentHashing {
    private let contentHasher: ContentHashing
    private let platformConditionContentHasher: PlatformConditionContentHashing

    // MARK: - Init

    public init(
        contentHasher: ContentHashing,
        platformConditionContentHasher: PlatformConditionContentHashing
    ) {
        self.contentHasher = contentHasher
        self.platformConditionContentHasher = platformConditionContentHasher
    }

    // MARK: - SourceFilesContentHashing

    /// Returns a unique hash that identifies an arry of sourceFiles
    /// First it hashes the content of every file and append to every hash the compiler flags of the file. It assumes the files
    /// are always sorted the same way.
    /// Then it hashes again all partial hashes to get a unique identifier that represents a group of source files together with
    /// their compiler flags
    public func hash(identifier: String, sources: [SourceFile]) throws -> MerkelNode {
        var children: [MerkelNode] = []

        for source in sources.sorted(by: { $0.path < $1.path }) {
            if let hash = source.contentHash {
                children.append(MerkelNode(
                    hash: hash,
                    identifier: source.path.pathString,
                    children: []
                ))
            } else {
                var sourceChildren: [MerkelNode] = []
                sourceChildren.append(MerkelNode(
                    hash: try contentHasher.hash(path: source.path),
                    identifier: "content",
                    children: []
                ))

                if let compilerFlags = source.compilerFlags {
                    sourceChildren.append(MerkelNode(
                        hash: try contentHasher.hash(compilerFlags),
                        identifier: "compilerFlags",
                        children: []
                    ))
                }

                if let codeGen = source.codeGen {
                    sourceChildren.append(MerkelNode(
                        hash: try contentHasher.hash(codeGen.rawValue),
                        identifier: "codeGen",
                        children: []
                    ))
                }

                if let compilationCondition = source.compilationCondition {
                    sourceChildren.append(try platformConditionContentHasher.hash(
                        identifier: "compilationCondition",
                        platformCondition: compilationCondition
                    ))
                }

                children.append(MerkelNode(
                    hash: try contentHasher.hash(sourceChildren.map(\.hash)),
                    identifier: source.path.pathString,
                    children: sourceChildren
                ))
            }
        }

        return MerkelNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: identifier,
            children: children
        )
    }
}
