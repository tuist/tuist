import ProjectDescription
import TuistGraph

extension TuistGraph.ProjectOption {
    /// Maps a ProjectDescription.ProjectOption instance into a TuistGraph.ProjectOption instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of project options.
    static func from(manifest: ProjectDescription.ProjectOption) -> TuistGraph.ProjectOption {
        switch manifest {
        case let .automaticSchemesGrouping(grouping):
            switch grouping {
            case .singleScheme:
                return .automaticSchemesGrouping(.singleScheme)
            case let .byName(build, test, run):
                return .automaticSchemesGrouping(.byName(build: build, test: test, run: run))
            case .notGrouped:
                return .automaticSchemesGrouping(.notGrouped)
            }
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
