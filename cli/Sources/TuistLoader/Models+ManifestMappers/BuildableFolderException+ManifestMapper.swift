import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderException {
    static func from(
        manifest: ProjectDescription.BuildableFolderException,
        buildableFolder: AbsolutePath
    ) throws -> Self {
        let excluded = try manifest.excluded.map { buildableFolder.appending(try RelativePath(validating: $0)) }
        let compilerFlags = Dictionary(uniqueKeysWithValues: try manifest.compilerFlags.map {
            (buildableFolder.appending(try RelativePath(validating: $0.0)), $0.1)
        })
        return Self(excluded: excluded, compilerFlags: compilerFlags)
    }
}
