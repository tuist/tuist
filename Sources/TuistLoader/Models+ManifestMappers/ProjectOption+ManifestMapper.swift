import ProjectDescription
import TuistGraph

extension TuistGraph.ProjectOption {
    /// Maps a ProjectDescription.ProjectOption instance into a TuistGraph.ProjectOption instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of project options.
    static func from(manifest: ProjectDescription.ProjectOption) -> TuistGraph.ProjectOption {
        switch manifest {
        case .disableBundleAccessors:
            return .disableBundleAccessors
        case .disableSynthesizedResourceAccessors:
            return .disableSynthesizedResourceAccessors
        case let .textSettings(usesTabs, indentWidth, tabWidth, wrapsLines):
            return .textSettings(
                .init(
                    usesTabs: usesTabs,
                    indentWidth: indentWidth,
                    tabWidth: tabWidth,
                    wrapsLines: wrapsLines
                )
            )
        }
    }
}
