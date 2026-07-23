import Foundation
import Path
import ProjectDescription
import TuistSupport
import XcodeGraph

struct SettingsMapper {
    init(
        headerSearchPaths: [String],
        mainRelativePath: RelativePath,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        enabledTraits: Set<String> = []
    ) {
        self.headerSearchPaths = headerSearchPaths
        self.settings = settings
        self.mainRelativePath = mainRelativePath
        self.enabledTraits = enabledTraits
    }

    private let headerSearchPaths: [String]
    private let mainRelativePath: RelativePath
    private let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting]
    private let enabledTraits: Set<String>

    func mapSettings() throws -> XcodeGraph.SettingsDictionary {
        var resolvedSettings = try settingsDictionary()

        for platform in XcodeGraph.Platform.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let platformSettings = try settingsDictionary(for: platform)
            resolvedSettings.overlay(with: platformSettings, for: platform)
        }

        return resolvedSettings
    }

    func settingsForBuildConfiguration(
        _ buildConfiguration: String
    ) throws -> XcodeGraph.SettingsDictionary {
        try map(
            settings: settings.filter { setting in
                return setting.hasConditions && setting.condition?.config?.uppercasingFirst == buildConfiguration
            }
        )
    }

    // swiftlint:disable:next function_body_length
    func settingsDictionary(for platform: XcodeGraph.Platform? = nil) throws -> XcodeGraph.SettingsDictionary {
        let platformSettings = try settings(for: platform?.rawValue)

        return try map(
            settings: platformSettings,
            headerSearchPaths: headerSearchPaths
        )
    }

    private func map(
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        headerSearchPaths: [String] = [],
        defines: [String: String] = [:],
        swiftDefines: [String] = []
    ) throws -> XcodeGraph.SettingsDictionary {
        var headerSearchPaths = headerSearchPaths
        var defines = defines
        var swiftDefines = swiftDefines
        var cFlags: [String] = []
        var cxxFlags: [String] = []
        var swiftFlags: [String] = []
        var linkerFlags: [String] = []

        var settingsDictionary = XcodeGraph.SettingsDictionary()
        for setting in settings {
            switch (setting.tool, setting.name) {
            case (.swift, .defaultIsolation):
                switch setting.value {
                case ["nonisolated"], ["nil"]:
                    settingsDictionary["SWIFT_DEFAULT_ACTOR_ISOLATION"] = "nonisolated"
                case ["MainActor"], ["MainActor.self"], ["main-actor"]:
                    settingsDictionary["SWIFT_DEFAULT_ACTOR_ISOLATION"] = "MainActor"
                default:
                    break
                }
            case (_, .defaultIsolation):
                break
            case (.swift, .interoperabilityMode):
                if setting.value == ["Cxx"] {
                    settingsDictionary["SWIFT_OBJC_INTEROP_MODE"] = "objcxx"
                } else if setting.value == ["C"] {
                    settingsDictionary["SWIFT_OBJC_INTEROP_MODE"] = "objc"
                }
            case (_, .interoperabilityMode):
                break
            case (.c, .headerSearchPath), (.cxx, .headerSearchPath):
                headerSearchPaths.append("$(SRCROOT)/\(mainRelativePath.pathString)/\(setting.value[0])".quotedIfContainsSpaces)
            case (.c, .define), (.cxx, .define):
                let (name, value) = setting.extractDefine
                defines[name] = value
            case (.c, .unsafeFlags):
                cFlags.append(contentsOf: setting.value)
            case (.c, .disableWarning):
                cFlags.append("-Wno-\(setting.value[0])")
            case (.cxx, .unsafeFlags):
                cxxFlags.append(contentsOf: setting.value)
            case (.cxx, .disableWarning):
                cxxFlags.append("-Wno-\(setting.value[0])")
            case (.swift, .define):
                swiftDefines.append(contentsOf: setting.value)
            case (.swift, .unsafeFlags):
                swiftFlags.append(contentsOf: setting.value)
            case (.swift, .disableWarning):
                swiftFlags.append("-Wno-\(setting.value[0])")
            case (.c, .treatAllWarnings):
                cFlags.append(setting.treatAllWarningsFlag(errorFlag: "-Werror", warningFlag: "-Wno-error"))
            case (.cxx, .treatAllWarnings):
                cxxFlags.append(setting.treatAllWarningsFlag(errorFlag: "-Werror", warningFlag: "-Wno-error"))
            case (.swift, .treatAllWarnings):
                swiftFlags.append(setting.treatAllWarningsFlag(
                    errorFlag: "-warnings-as-errors",
                    warningFlag: "-no-warnings-as-errors"
                ))
            case (.c, .treatWarning):
                cFlags.append(setting.treatWarningFlag(errorPrefix: "-Werror=", warningPrefix: "-Wno-error="))
            case (.cxx, .treatWarning):
                cxxFlags.append(setting.treatWarningFlag(errorPrefix: "-Werror=", warningPrefix: "-Wno-error="))
            case (.swift, .treatWarning):
                swiftFlags.append(contentsOf: setting.treatSwiftWarningFlags())
            case (.c, .enableWarning):
                cFlags.append("-W\(setting.value[0])")
            case (.cxx, .enableWarning):
                cxxFlags.append("-W\(setting.value[0])")
            case (.swift, .enableUpcomingFeature):
                swiftFlags.append("-enable-upcoming-feature \"\(setting.value[0])\"")
            case (.swift, .enableExperimentalFeature):
                swiftFlags.append("-enable-experimental-feature \"\(setting.value[0])\"")
            case (.swift, .strictMemorySafety):
                swiftFlags.append("-strict-memory-safety")
                // If the value indicates errors enforcement, treat warnings as errors
                if setting.value.first?.lowercased() == "errors" {
                    swiftFlags.append("-Werror=StrictMemorySafety")
                }
            case (.swift, .swiftLanguageMode):
                // TODO: Use -language-mode instead of -swift-version when Xcode 15 support is removed.
                // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0441-formalize-language-mode-terminology.md#swift-compiler-option
                swiftFlags.append("-swift-version \(setting.value[0])")

                // Control the language mode for an Xcode project or target by setting the XCConfig SWIFT_VERSION
                // https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/swift6mode
                settingsDictionary["SWIFT_VERSION"] = "\(setting.value[0])"
            case (.linker, .unsafeFlags):
                linkerFlags.append(contentsOf: setting.value)
            case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                // Handled as dependency
                continue
            case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                 (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                 (.linker, .headerSearchPath), (.linker, .define), (.linker, .disableWarning),
                 (_, .enableUpcomingFeature), (_, .enableExperimentalFeature), (_, .swiftLanguageMode),
                 (_, .strictMemorySafety), (.linker, .treatAllWarnings), (.linker, .treatWarning),
                 (.swift, .enableWarning), (.linker, .enableWarning):
                throw PackageInfoMapperError.unsupportedSetting(setting.tool, setting.name)
            }
        }

        if !headerSearchPaths.isEmpty {
            settingsDictionary["HEADER_SEARCH_PATHS"] = .array(["$(inherited)"] + headerSearchPaths.map { $0 })
        }

        if !defines.isEmpty {
            let sortedDefines = defines.sorted { $0.key < $1.key }
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)"] + sortedDefines
                .map { key, value in
                    "\(key)=\(value.spm_shellEscaped())"
                }
            )
        }

        if !swiftDefines.isEmpty {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .array(["$(inherited)"] + swiftDefines)
        }

        if !cFlags.isEmpty {
            settingsDictionary["OTHER_CFLAGS"] = .array(["$(inherited)"] + cFlags)
        }

        if !cxxFlags.isEmpty {
            settingsDictionary["OTHER_CPLUSPLUSFLAGS"] = .array(["$(inherited)"] + cxxFlags)
        }

        if !swiftFlags.isEmpty {
            settingsDictionary["OTHER_SWIFT_FLAGS"] = .array(["$(inherited)"] + swiftFlags)
        }

        if !linkerFlags.isEmpty {
            settingsDictionary["OTHER_LDFLAGS"] = .array(["$(inherited)"] + linkerFlags)
        }

        return settingsDictionary
    }

    /// `nil` means settings without a platform restriction.
    ///
    /// A setting is included when both its platform and trait conditions are
    /// satisfied by the current context. A `.when(traits:)` setting whose trait
    /// intersects `enabledTraits` is treated as unconditional w.r.t. traits,
    /// mirroring SwiftPM's own evaluation of trait-conditional build settings
    /// (SE-0450).
    private func settings(for platformName: String?) throws
        -> [PackageInfo.Target.TargetBuildSettingDescription.Setting]
    {
        settings.filter { setting in
            // Config-conditional settings are handled by `settingsForBuildConfiguration`.
            if setting.condition?.config != nil { return false }
            guard traitConditionMatches(setting.condition) else { return false }

            let platformNames = expandedPlatformNames(in: setting.condition)
            let hasPlatformRestriction = !platformNames.isEmpty

            if let platformName {
                return !hasPlatformRestriction || platformNames.contains(platformName)
            } else {
                return !hasPlatformRestriction
            }
        }
    }

    private func traitConditionMatches(_ condition: PackageInfo.PackageConditionDescription?) -> Bool {
        guard let traits = condition?.traits, !traits.isEmpty else { return true }
        return !enabledTraits.isDisjoint(with: traits)
    }

    private func expandedPlatformNames(
        in condition: PackageInfo.PackageConditionDescription?
    ) -> [String] {
        let platformNames = condition?.platformNames ?? []
        if platformNames.contains("maccatalyst") {
            return platformNames + ["ios"]
        }
        return platformNames
    }
}

extension PackageInfo.Target.TargetBuildSettingDescription.Setting {
    fileprivate var extractDefine: (name: String, value: String) {
        let define = value[0]
        if define.contains("=") {
            let split = define.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (name: String(split[0]), value: String(split[1]))
        } else {
            return (name: define, value: "1")
        }
    }

    fileprivate func treatAllWarningsFlag(errorFlag: String, warningFlag: String) -> String {
        value[0] == "error" ? errorFlag : warningFlag
    }

    fileprivate func treatWarningFlag(errorPrefix: String, warningPrefix: String) -> String {
        let prefix = value[1] == "error" ? errorPrefix : warningPrefix
        return "\(prefix)\(value[0])"
    }

    fileprivate func treatSwiftWarningFlags() -> [String] {
        let flag = value[1] == "error" ? "-Werror" : "-Wwarning"
        return [flag, value[0]]
    }
}
