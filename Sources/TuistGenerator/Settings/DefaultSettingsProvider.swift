import Foundation
import TuistCore
import XcodeProj

public protocol DefaultSettingsProviding {
    func projectSettings(project: Project,
                         buildConfiguration: BuildConfiguration) throws -> [String: SettingValue]

    func targetSettings(target: Target,
                        buildConfiguration: BuildConfiguration) throws -> [String: SettingValue]
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
        "CLANG_CXX_LIBRARY",
        "CLANG_ENABLE_MODULES",
        "CLANG_ENABLE_OBJC_ARC",
        "CLANG_ENABLE_OBJC_WEAK",
        "COPY_PHASE_STRIP",
        "ENABLE_STRICT_OBJC_MSGSEND",
        "GCC_C_LANGUAGE_STANDARD",
        "GCC_NO_COMMON_BLOCKS",
        "PRODUCT_NAME",
    ]

    private static let essentialTargetSettings: Set<String> = [
        "SDKROOT",
        "CODE_SIGN_IDENTITY",
        "LD_RUNPATH_SEARCH_PATHS",
        "VALIDATE_PRODUCT",
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
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES",
        "WRAPPER_EXTENSION",
    ]

    public init() {}

    // MARK: - DefaultSettingsProviding

    public func projectSettings(project: Project,
                                buildConfiguration: BuildConfiguration) throws -> [String: SettingValue] {
        let settingsHelper = SettingsHelper()
        let defaultSettings = project.settings.defaultSettings
        let variant = settingsHelper.variant(buildConfiguration)
        let projectDefaultAll = try BuildSettingsProvider.projectDefault(variant: .all).toSettings()
        let projectDefaultVariant = try BuildSettingsProvider.projectDefault(variant: variant).toSettings()
        let filter = createFilter(defaultSettings: defaultSettings,
                                  essentialKeys: DefaultSettingsProvider.essentialProjectSettings)

        var settings: [String: SettingValue] = [:]
        settingsHelper.extend(buildSettings: &settings, with: projectDefaultAll)
        settingsHelper.extend(buildSettings: &settings, with: projectDefaultVariant)
        return settings.filter(filter)
    }

    public func targetSettings(target: Target,
                               buildConfiguration: BuildConfiguration) throws -> [String: SettingValue] {
        let settingsHelper = SettingsHelper()
        let defaultSettings = target.settings?.defaultSettings ?? .recommended
        let product = settingsHelper.settingsProviderProduct(target)
        let platform = settingsHelper.settingsProviderPlatform(target)
        let variant = settingsHelper.variant(buildConfiguration)
        let targetDefaultAll = try BuildSettingsProvider.targetDefault(variant: .all,
                                                                       platform: platform,
                                                                       product: product,
                                                                       swift: true).toSettings()
        let targetDefaultVariant = try BuildSettingsProvider.targetDefault(variant: variant,
                                                                           platform: platform,
                                                                           product: product,
                                                                           swift: true).toSettings()
        let filter = createFilter(defaultSettings: defaultSettings,
                                  essentialKeys: DefaultSettingsProvider.essentialTargetSettings)

        var settings: [String: SettingValue] = [:]
        settingsHelper.extend(buildSettings: &settings, with: targetDefaultAll)
        settingsHelper.extend(buildSettings: &settings, with: targetDefaultVariant)
        return settings.filter(filter)
    }

    // MARK: - Private

    private func createFilter(defaultSettings: DefaultSettings, essentialKeys: Set<String>) -> (String, SettingValue) -> Bool {
        switch defaultSettings {
        case .essential:
            return { key, _ in essentialKeys.contains(key) }
        case .recommended:
            return { _, _ in true }
        case .none:
            return { _, _ in false }
        }
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
    func toSettings() throws -> [String: SettingValue] {
        return try mapValues { value in
            switch value {
            case let value as String:
                return .string(value)
            case let value as [String]:
                return .array(value)
            default:
                throw BuildSettingsError.invalidValue(value)
            }
        }
    }
}
