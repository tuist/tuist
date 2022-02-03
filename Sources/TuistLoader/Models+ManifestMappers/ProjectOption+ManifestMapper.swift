import ProjectDescription
import TuistGraph

extension TuistGraph.ProjectOption {
    /// Maps a ProjectDescription.ProjectOption instance into a TuistGraph.ProjectOption instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of project options.
    static func from(manifest: ProjectDescription.ProjectOption) -> Self {
        switch manifest {
        case let .automaticSchemesOptions(options):
            switch options {
            case let .enabled(targetSchemesGrouping, codeCoverageEnabled, testingOptions):
                return .automaticSchemesOptions(.enabled(
                    targetSchemesGrouping: .from(manifest: targetSchemesGrouping),
                    codeCoverageEnabled: codeCoverageEnabled,
                    testingOptions: .from(manifest: testingOptions)
                ))
            case .disabled:
                return .automaticSchemesOptions(.disabled)
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

extension TuistGraph.ProjectOption.AutomaticSchemesOptions.TargetSchemesGrouping {
    static func from(
        manifest: ProjectDescription.ProjectOption.AutomaticSchemesOptions.TargetSchemesGrouping
    ) -> Self {
        switch manifest {
        case .singleScheme:
            return .singleScheme
        case let .byNameSuffix(build, test, run):
            return .byNameSuffix(build: build, test: test, run: run)
        case .notGrouped:
            return .notGrouped
        }
    }
}
