import ProjectDescription
import XcodeGraph

extension XcodeGraph.Project.Options {
    /// Maps a ProjectDescription.ProjectOption instance into a XcodeGraph.ProjectOption instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of project options.
    static func from(manifest: ProjectDescription.Project.Options) -> Self {
        .init(
            automaticSchemesOptions: .from(manifest: manifest.automaticSchemesOptions),
            disableBundleAccessors: manifest.disableBundleAccessors,
            disableShowEnvironmentVarsInScriptPhases: manifest.disableShowEnvironmentVarsInScriptPhases,
            disableSynthesizedResourceAccessors: manifest.disableSynthesizedResourceAccessors,
            textSettings: .init(
                usesTabs: manifest.textSettings.usesTabs,
                indentWidth: manifest.textSettings.indentWidth,
                tabWidth: manifest.textSettings.tabWidth,
                wrapsLines: manifest.textSettings.wrapsLines
            )
        )
    }
}

extension XcodeGraph.Project.Options.AutomaticSchemesOptions {
    static func from(
        manifest: ProjectDescription.Project.Options.AutomaticSchemesOptions
    ) -> Self {
        switch manifest {
        case let .enabled(
            targetSchemesGrouping,
            codeCoverageEnabled,
            testingOptions,
            testLanguage,
            testRegion,
            testScreenCaptureFormat,
            runLanguage,
            runRegion
        ):
            return .enabled(
                targetSchemesGrouping: .from(manifest: targetSchemesGrouping),
                codeCoverageEnabled: codeCoverageEnabled,
                testingOptions: .from(manifest: testingOptions),
                testLanguage: testLanguage?.identifier,
                testRegion: testRegion,
                testScreenCaptureFormat: testScreenCaptureFormat.map { .from(manifest: $0) },
                runLanguage: runLanguage?.identifier,
                runRegion: runRegion
            )
        case .disabled:
            return .disabled
        }
    }
}

extension XcodeGraph.Project.Options.AutomaticSchemesOptions.TargetSchemesGrouping {
    static func from(
        manifest: ProjectDescription.Project.Options.AutomaticSchemesOptions.TargetSchemesGrouping
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
