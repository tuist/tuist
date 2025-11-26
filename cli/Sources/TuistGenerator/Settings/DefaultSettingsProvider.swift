import Foundation
import Path
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

public protocol DefaultSettingsProviding {
    func projectSettings(
        project: Project,
        buildConfiguration: BuildConfiguration
    ) async throws -> SettingsDictionary

    func targetSettings(
        target: Target,
        project: Project,
        buildConfiguration: BuildConfiguration,
        graphTraverser: GraphTraversing
    ) async throws -> SettingsDictionary
}

public final class DefaultSettingsProvider: DefaultSettingsProviding {
    private static let essentialProjectSettings: Set<String> = [
        "ALWAYS_SEARCH_USER_PATHS",
        "DEBUG_INFORMATION_FORMAT",
        "ENABLE_NS_ASSERTIONS",
        "ENABLE_TESTABILITY",
        "GCC_DYNAMIC_NO_PIC",
        "GCC_OPTIMIZATION_LEVEL",
        "GCC_PREPROCESSOR_DEFINITIONS",
        "MTL_ENABLE_DEBUG_INFO",
        "ONLY_ACTIVE_ARCH",
        "CLANG_ANALYZER_NONNULL",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION",
        "CLANG_CXX_LANGUAGE_STANDARD",
        "CLANG_ENABLE_MODULES",
        "CLANG_ENABLE_OBJC_ARC",
        "CLANG_ENABLE_OBJC_WEAK",
        "COPY_PHASE_STRIP",
        "ENABLE_STRICT_OBJC_MSGSEND",
        "GCC_C_LANGUAGE_STANDARD",
        "GCC_NO_COMMON_BLOCKS",
        "PRODUCT_NAME",
        "VALIDATE_PRODUCT",
    ]

    private static let essentialTargetSettings: Set<String> = [
        "SDKROOT",
        "CODE_SIGN_IDENTITY",
        "LD_RUNPATH_SEARCH_PATHS",
        "SWIFT_OPTIMIZATION_LEVEL",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
        "CURRENT_PROJECT_VERSION",
        "DEFINES_MODULE",
        "DYLIB_COMPATIBILITY_VERSION",
        "DYLIB_CURRENT_VERSION",
        "DYLIB_INSTALL_NAME_BASE",
        "INSTALL_PATH",
        "PRODUCT_NAME",
        "SKIP_INSTALL",
        "VERSION_INFO_PREFIX",
        "VERSIONING_SYSTEM",
        "TARGETED_DEVICE_FAMILY",
        "EXECUTABLE_PREFIX",
        "COMBINE_HIDPI_IMAGES",
        "WRAPPER_EXTENSION",
        "SWIFT_VERSION",
        "TEST_TARGET_NAME",
        "TEST_HOST",
        "BUNDLE_LOADER",
    ]

    /// These are not needed or are computed elsewhere so we exclude them.
    private static let multiplatformExcludedSettingsKeys = Set([
        "COMBINE_HIDPI_IMAGES",
        "SDKROOT",
        "CODE_SIGN_IDENTITY",
        "APPLICATION_EXTENSION_API_ONLY",
        "FRAMEWORK_VERSION",
        "TARGETED_DEVICE_FAMILY",
    ])

    /// Key is `Version` which describes from which version of Xcode are values available for
    private static let xcodeVersionSpecificSettings: [Version: Set<String>] = [
        Version(11, 0, 0): [
            "ENABLE_PREVIEWS",
        ],
    ]

    public init() {}

    // MARK: - DefaultSettingsProviding

    public func projectSettings(
        project: Project,
        buildConfiguration: BuildConfiguration
    ) async throws -> SettingsDictionary {
        let settingsHelper = SettingsHelper()
        let defaultSettings = project.settings.defaultSettings
        let variant = settingsHelper.variant(buildConfiguration)
        let projectDefaultAll = BuildSettingsProvider.projectDefault(variant: .all).toSettings()
        let projectDefaultVariant = BuildSettingsProvider.projectDefault(variant: variant).toSettings()
        let filter = try await createFilter(
            defaultSettings: defaultSettings,
            essentialKeys: DefaultSettingsProvider.essentialProjectSettings
        )

        var settings: SettingsDictionary = [:]
        settingsHelper.extend(buildSettings: &settings, with: projectDefaultAll)
        settingsHelper.extend(buildSettings: &settings, with: projectDefaultVariant)
        return settings.filter(filter)
    }

    public func targetSettings(
        target: Target,
        project: Project,
        buildConfiguration: BuildConfiguration,
        graphTraverser: GraphTraversing
    ) async throws -> SettingsDictionary {
        var settings: SettingsDictionary = [:]
        if target.isMultiplatform {
            // Loop over platforms in a deterministic order.
            for platform in Platform.allCases where target.supports(platform) {
                let platformSetting = try await targetSettings(
                    target: target,
                    project: project,
                    platform: platform,
                    buildConfiguration: buildConfiguration,
                    graphTraverser: graphTraverser
                )

                let filteredSettings = platformSetting
                    .filter { !DefaultSettingsProvider.multiplatformExcludedSettingsKeys.contains($0.key) }

                for (key, newValue) in filteredSettings {
                    if settings[key] == nil {
                        settings[key] = newValue
                    } else if settings[key] != newValue {
                        let newKey = "\(key)[sdk=\(platform.xcodeSdkRoot)*]"
                        settings[newKey] = newValue
                        if platform.hasSimulators, let simulatorSDK = platform.xcodeSimulatorSDK {
                            let newKey = "\(key)[sdk=\(simulatorSDK)*]"
                            settings[newKey] = newValue
                        }
                    }
                }
            }
        } else if let platform = target.supportedPlatforms.first {
            settings = try await targetSettings(
                target: target,
                project: project,
                platform: platform,
                buildConfiguration: buildConfiguration,
                graphTraverser: graphTraverser
            )
        }

        // This allows running the project directly without specifying `CODE_SIGN_IDENTITY`.
        if target.supportsCatalyst {
            settings.overlay(with: ["CODE_SIGN_IDENTITY": "-"], for: .macOS)
        }

        return settings
    }

    private func targetSettings(
        target: Target,
        project: Project,
        platform: Platform,
        buildConfiguration: BuildConfiguration,
        graphTraverser: GraphTraversing
    ) async throws -> SettingsDictionary {
        let settingsHelper = SettingsHelper()
        let defaultSettings = target.settings?.defaultSettings ?? project.settings.defaultSettings
        let product = settingsHelper.settingsProviderProduct(target)
        let settingsPlatform = settingsHelper.settingsProviderPlatform(platform)
        let variant = settingsHelper.variant(buildConfiguration)
        let targetDefaultAll = BuildSettingsProvider.targetDefault(
            variant: .all,
            platform: settingsPlatform,
            product: product,
            swift: true
        ).toSettings()
        let additionalTargetDefaults = additionalTargetSettings(for: target)
        let targetDefaultVariant = BuildSettingsProvider.targetDefault(
            variant: variant,
            platform: settingsPlatform,
            product: product,
            swift: true
        ).toSettings()
        let filter = try await createFilter(
            defaultSettings: defaultSettings,
            essentialKeys: DefaultSettingsProvider.essentialTargetSettings,
            newXcodeKeys: DefaultSettingsProvider.xcodeVersionSpecificSettings
        )
        let mergeableSettings = mergeableSettings(for: target, configuration: buildConfiguration)
        var settings: SettingsDictionary = [:]
        settingsHelper.extend(buildSettings: &settings, with: targetDefaultAll)
        settingsHelper.extend(buildSettings: &settings, with: additionalTargetDefaults)
        settingsHelper.extend(buildSettings: &settings, with: targetDefaultVariant)
        settingsHelper.extend(buildSettings: &settings, with: mergeableSettings)
        settingsHelper.extend(buildSettings: &settings, with: projectOverridableTargetDefaultSettings(for: project))
        settingsHelper.extend(
            buildSettings: &settings,
            with: testBundleTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: project.path)
        )
        return settings.filter(filter)
    }

    // MARK: - Private

    private func mergeableSettings(for target: Target, configuration: BuildConfiguration) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]
        if target.mergeable {
            settings["MAKE_MERGEABLE"] = "YES"
            settings["MERGEABLE_LIBRARY"] = "YES"
        }
        if target.mergedBinaryType == .automatic {
            settings["MERGED_BINARY_TYPE"] = "automatic"
        } else if case let .manual(mergeableDependencies) = target.mergedBinaryType {
            settings["MERGED_BINARY_TYPE"] = "manual"
            let frameworkLinkage = configuration.variant == .release ? "-merge_framework" : "-reexport_framework"
            settings["OTHER_LDFLAGS"] = .array(mergeableDependencies.map { "-Wl,\(frameworkLinkage),\($0)" })
        }
        return settings
    }

    private func createFilter(
        defaultSettings: DefaultSettings,
        essentialKeys: Set<String>,
        newXcodeKeys: [Version: Set<String>] = [:]
    ) async throws -> (String, SettingValue) -> Bool {
        switch defaultSettings {
        case let .essential(excludedKeys):
            return { key, _ in essentialKeys.contains(key) && !excludedKeys.contains(key) }
        case let .recommended(excludedKeys):
            let xcodeVersion = try await XcodeController.current.selectedVersion()
            return { key, _ in
                // Filter keys that are from higher Xcode version than current (otherwise return true)
                !newXcodeKeys
                    .filter { $0.key > xcodeVersion }
                    .values.flatMap { $0 }.contains(key) &&
                    !excludedKeys.contains(key)
            }
        case .none:
            return { _, _ in false }
        }
    }

    private func projectOverridableTargetDefaultSettings(for project: Project) -> SettingsDictionary {
        var settings = SettingsDictionary()
        // If swift version is already specified at the project level settings, there is no need to
        // override it with a default version. This allows users to set `SWIFT_VERSION`
        // at the project level and it automatically applying to all targets without it getting
        // overwritten.
        if project.settings.base["SWIFT_VERSION"] == nil {
            settings["SWIFT_VERSION"] = "5.0"
        }
        return settings
    }

    private func additionalTargetSettings(for target: Target) -> SettingsDictionary {
        if target.isExclusiveTo(.watchOS), target.product == .app {
            return [
                "LD_RUNPATH_SEARCH_PATHS": [
                    "$(inherited)",
                    "@executable_path/Frameworks",
                ],
            ]
        } else if target.product == .macro {
            return [
                "SKIP_INSTALL": "YES",
            ]
        } else {
            return [:]
        }
    }

    private func testBundleTargetDerivedSettings(
        target: Target,
        graphTraverser: GraphTraversing,
        projectPath: AbsolutePath
    ) -> SettingsDictionary {
        guard target.product.testsBundle else {
            return [:]
        }

        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: projectPath, name: target.name).sorted()
        let appDependency = targetDependencies.first { $0.target.product.canHostTests() }

        guard let app = appDependency else {
            return [:]
        }

        var settings: SettingsDictionary = [:]
        settings["TEST_TARGET_NAME"] = .string("\(app.target.name)")
        if target.product == .unitTests {
            settings["TEST_HOST"] =
                .string(
                    "$(BUILT_PRODUCTS_DIR)/\(app.target.productNameWithExtension)/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/\(app.target.productName)"
                )
            settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        }

        return settings
    }
}

enum BuildSettingsError: FatalError {
    case invalidValue(Any)

    var description: String {
        switch self {
        case let .invalidValue(value):
            return "Cannot convert \"\(value)\" to SettingValue type"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidValue:
            return .bug
        }
    }
}

extension BuildSettings {
    func toSettings() -> SettingsDictionary {
        mapValues { value in
            switch value {
            case let .string(value):
                return .string(value)
            case let .array(value):
                return .array(value)
            }
        }
    }
}

extension SettingsDictionary {
    func toBuildSettings() -> BuildSettings {
        mapValues { value in
            switch value {
            case let .string(value):
                return .string(value)
            case let .array(value):
                return .array(value)
            }
        }
    }
}
