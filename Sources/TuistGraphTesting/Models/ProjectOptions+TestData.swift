import Foundation
@testable import TuistGraph

extension Project.Options {
    public static func automaticSchemesOptions() -> AutomaticSchemesOptions {
        .enabled(
            targetSchemesGrouping: .byNameSuffix(
                build: ["Implementation", "Interface", "Mocks", "Testing"],
                test: ["Tests", "IntegrationTests", "UITests", "SnapshotTests"],
                run: ["App", "Demo"]
            ),
            codeCoverageEnabled: false,
            testingOptions: []
        )
    }

    public static func test(
        automaticSchemesOptions: AutomaticSchemesOptions = automaticSchemesOptions(),
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

    public static func testOptions(
        automaticSchemesOptions: AutomaticSchemesOptions = automaticSchemesOptions(),
        bundleAccessorsOptions: BundleAccessorOptions = .disabled,
        disableShowEnvironmentVarsInScriptPhases: Bool = false,
        disableSynthesizedResourceAccessors: Bool = false,
        textSettings: TextSettings = .init(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
    ) -> Self {
        .init(
            automaticSchemesOptions: automaticSchemesOptions,
            bundleAccessorsOptions: bundleAccessorsOptions,
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
