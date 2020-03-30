import Foundation
import TuistCore

public protocol SourceFilesContentHashing {
    func hash(sources: [Target.SourceFile]) throws -> String
}

public final class SourceFilesContentHasher: SourceFilesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }


    // MARK: - SourceFilesContentHashing

    /// Returns a unique hash that identifies an arry of sourceFiles
    /// First it hashes the content of every file, in a specific order, and append to every hash the compiler flags of the file
    /// Then it hashes again all partial hashes to get a unique identifier that represents a group of source files together with their compiler flags
    public func hash(sources: [Target.SourceFile]) throws -> String {
        let sortedSources = sources.sorted(by: { $0.path < $1.path })
        var stringsToHash: [String] = []
        for source in sortedSources {
            var sourceHash = try contentHasher.hash(source.path)
            if let compilerFlags = source.compilerFlags {
                sourceHash += try contentHasher.hash(compilerFlags)
            }
            stringsToHash.append(sourceHash)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
