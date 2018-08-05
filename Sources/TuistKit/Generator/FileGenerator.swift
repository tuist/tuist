import Basic
import Foundation
import xcodeproj

protocol FileGenerating: AnyObject {
    func generateFile(path: AbsolutePath,
                      in group: PBXGroup,
                      sourceRootPath: AbsolutePath) throws -> PBXFileReference
}

final class FileGenerator: FileGenerating {
    func generateFile(path: AbsolutePath,
                      in group: PBXGroup,
                      sourceRootPath: AbsolutePath) throws -> PBXFileReference {
        return try group.addFile(at: path, sourceTree: .group, sourceRoot: sourceRootPath)
    }
}
