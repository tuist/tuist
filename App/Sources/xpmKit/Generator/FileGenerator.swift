import Basic
import Foundation
import xcodeproj

/// Generation of files in an Xcode project.
protocol FileGenerating: AnyObject {
    /// Generates a file in the given group.
    ///
    /// - Parameters:
    ///   - path: absolute path to the file.
    ///   - group: group where the file will be added.
    ///   - sourceRootPath: path to the folder that contains the Xcode project that is being generated.
    ///   - context: generation context.
    /// - Throws: an error if the generation fails.
    func generateFile(path: AbsolutePath,
                      in group: PBXGroup,
                      sourceRootPath: AbsolutePath,
                      context: GeneratorContexting) throws -> PBXFileReference
}

final class FileGenerator: FileGenerating {
    /// Generates a file in the given group.
    ///
    /// - Parameters:
    ///   - path: absolute path to the file.
    ///   - group: group where the file will be added.
    ///   - sourceRootPath: path to the folder that contains the Xcode project that is being generated.
    ///   - context: generation context.
    /// - Throws: an error if the generation fails.
    func generateFile(path: AbsolutePath,
                      in group: PBXGroup,
                      sourceRootPath: AbsolutePath,
                      context _: GeneratorContexting) throws -> PBXFileReference {
        return try group.addFile(at: path, sourceTree: .group, sourceRoot: sourceRootPath)
    }
}
