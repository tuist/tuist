import Foundation
import TuistCore

protocol SourceFilesContentHashing {
    func hash(sources: [Target.SourceFile]) throws -> String
}

public final class SourceFilesContentHasher {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    // First, hash the content of every file, in a specific order, and append to every hash the compiler flags of the file
    // Then hash again all these hashes to get a unique identifier that represents a group of source files with their compiler flags

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
