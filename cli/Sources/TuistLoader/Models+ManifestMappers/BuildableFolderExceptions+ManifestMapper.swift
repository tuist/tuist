import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderExceptions {
    static func from(
        manifest: ProjectDescription.BuildableFolderExceptions,
        buildableFolder: AbsolutePath
    ) throws -> Self {
        return Self(exceptions: try manifest.exceptions.map {
            try XcodeGraph.BuildableFolderException.from(manifest: $0, buildableFolder: buildableFolder)
        })
    }
}
