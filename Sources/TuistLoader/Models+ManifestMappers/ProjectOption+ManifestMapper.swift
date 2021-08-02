import ProjectDescription
import TuistGraph

extension TuistGraph.ProjectOption {
    /// Maps a ProjectDescription.ProjectOption instance into a TuistGraph.ProjectOption instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of project options.
    static func from(manifest: ProjectDescription.ProjectOption) -> TuistGraph.ProjectOption {
        switch manifest {
        case let .textSettings(textSettings):
            return .textSettings(.from(manifest: textSettings))
        }
    }
}
