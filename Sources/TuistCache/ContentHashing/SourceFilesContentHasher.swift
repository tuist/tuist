import Foundation
import TuistCore
import TuistGraph

public protocol SourceFilesContentHashing {
    func hash(sources: [SourceFile]) throws -> String
}

/// `SourceFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of source files, considering their content
public final class SourceFilesContentHasher: SourceFilesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - SourceFilesContentHashing

    /// Returns a unique hash that identifies an arry of sourceFiles
    /// First it hashes the content of every file and append to every hash the compiler flags of the file. It assumes the files are always sorted the same way.
    /// Then it hashes again all partial hashes to get a unique identifier that represents a group of source files together with their compiler flags
    public func hash(sources: [SourceFile]) throws -> String {
        var stringsToHash: [String] = []
        for source in sources.sorted(by: { $0.path < $1.path }) {
            if let hash = source.contentHash {
                stringsToHash.append(hash)
            } else {
                var sourceHash = try contentHasher.hash(path: source.path)
                if let compilerFlags = source.compilerFlags {
                    sourceHash += try contentHasher.hash(compilerFlags)
                }
                stringsToHash.append(sourceHash)
            }
        }
        return try contentHasher.hash(stringsToHash)
    }
}
