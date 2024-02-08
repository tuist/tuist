import Foundation
@testable import TuistGraph

extension Project.Options {
    public static func test(
        automaticSchemesOptions: AutomaticSchemesOptions = .enabled(
            targetSchemesGrouping: .byNameSuffix(
                build: ["Implementation", "Interface", "Mocks", "Testing"],
                test: ["Tests", "IntegrationTests", "UITests", "SnapshotTests"],
                run: ["App", "Demo"]
            ),
            codeCoverageEnabled: false,
            testingOptions: []
        ),
        disableBundleAccessors: Bool = false,
        disableShowEnvironmentVarsInScriptPhases: Bool = false,
        disableSynthesizedResourceAccessors: Bool = false,
        textSettings: TextSettings = .init(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
    ) -> Self {
        .init(
            automaticSchemesOptions: automaticSchemesOptions,
            disableBundleAccessors: disableBundleAccessors,
            disableShowEnvironmentVarsInScriptPhases: disableShowEnvironmentVarsInScriptPhases,
            disableSynthesizedResourceAccessors: disableSynthesizedResourceAccessors,
            textSettings: textSettings
        )
    }
}

extension Project.Options.TextSettings {
    public static func test(
        usesTabs: Bool? = true,
        indentWidth: UInt? = 2,
        tabWidth: UInt? = 2,
        wrapsLines: Bool? = true
    ) -> Self {
        .init(
            usesTabs: usesTabs,
            indentWidth: indentWidth,
            tabWidth: tabWidth,
            wrapsLines: wrapsLines
        )
    }
}
