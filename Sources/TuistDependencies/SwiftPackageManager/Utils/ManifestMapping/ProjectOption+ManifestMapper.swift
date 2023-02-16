import ProjectDescription
import TuistGraph

extension ProjectDescription.Project.Options {
    /// Maps a TuistGraph.ProjectOption instance into a ProjectDescription.ProjectOption instance.
    /// - Parameters:
    /// - manifest: Manifest representation of project options.
    static func from(manifest: TuistGraph.Project.Options) -> Self {
        options(
            automaticSchemesOptions: .from(manifest: manifest.automaticSchemesOptions),
            disableBundleAccessors: manifest.disableBundleAccessors,
            disableShowEnvironmentVarsInScriptPhases: manifest.disableShowEnvironmentVarsInScriptPhases,
            disableSynthesizedResourceAccessors: manifest.disableSynthesizedResourceAccessors,
            textSettings: .textSettings(
                usesTabs: manifest.textSettings.usesTabs,
                indentWidth: manifest.textSettings.indentWidth,
                tabWidth: manifest.textSettings.tabWidth,
                wrapsLines: manifest.textSettings.wrapsLines
            )
        )
    }
}

extension ProjectDescription.Project.Options.AutomaticSchemesOptions {
    static func from(
        manifest: TuistGraph.Project.Options.AutomaticSchemesOptions
    ) -> Self {
        switch manifest {
        case let .enabled(
            targetSchemesGrouping,
            codeCoverageEnabled,
            testingOptions,
            testLanguage,
            testRegion,
            runLanguage,
            runRegion
        ):
            return .enabled(
                targetSchemesGrouping: .from(manifest: targetSchemesGrouping),
                codeCoverageEnabled: codeCoverageEnabled,
                testingOptions: .from(manifest: testingOptions),
                testLanguage: testLanguage.map { .init(identifier: $0) },
                testRegion: testRegion,
                runLanguage: runLanguage.map { .init(identifier: $0) },
                runRegion: runRegion
            )
        case .disabled:
            return .disabled
        }
    }
}

extension ProjectDescription.Project.Options.AutomaticSchemesOptions.TargetSchemesGrouping {
    static func from(
        manifest: TuistGraph.Project.Options.AutomaticSchemesOptions.TargetSchemesGrouping
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
