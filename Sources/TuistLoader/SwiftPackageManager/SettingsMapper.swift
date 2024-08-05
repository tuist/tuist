import Foundation
import Path
import ProjectDescription
import TuistSupport
import XcodeGraph

struct SettingsMapper {
    init(
        headerSearchPaths: [String],
        mainRelativePath: RelativePath,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting]
    ) {
        self.headerSearchPaths = headerSearchPaths
        self.settings = settings
        self.mainRelativePath = mainRelativePath
    }

    private let headerSearchPaths: [String]
    private let mainRelativePath: RelativePath
    private let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting]

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
            headerSearchPaths: headerSearchPaths,
            defines: ["SWIFT_PACKAGE": "1"],
            swiftDefines: "SWIFT_PACKAGE"
        )
    }

    private func map(
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        headerSearchPaths: [String] = [],
        defines: [String: String] = [:],
        swiftDefines: String = ""
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
            case (.c, .headerSearchPath), (.cxx, .headerSearchPath):
                headerSearchPaths.append("$(SRCROOT)/\(mainRelativePath.pathString)/\(setting.value[0])".quotedIfContainsSpaces)
            case (.c, .define), (.cxx, .define):
                let (name, value) = setting.extractDefine
                defines[name] = value
            case (.c, .unsafeFlags):
                cFlags.append(contentsOf: setting.value)
            case (.cxx, .unsafeFlags):
                cxxFlags.append(contentsOf: setting.value)
            case (.swift, .define):
                swiftDefines.append(" \(setting.value[0])")
            case (.swift, .unsafeFlags):
                swiftFlags.append(contentsOf: setting.value)
            case (.swift, .enableUpcomingFeature):
                swiftFlags.append("-enable-upcoming-feature \"\(setting.value[0])\"")
            case (.swift, .enableExperimentalFeature):
                swiftFlags.append("-enable-experimental-feature \"\(setting.value[0])\"")
            case (.linker, .unsafeFlags):
                linkerFlags.append(contentsOf: setting.value)
            case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                // Handled as dependency
                continue
            case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                 (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                 (.linker, .headerSearchPath), (.linker, .define), (_, .enableUpcomingFeature),
                 (_, .enableExperimentalFeature):
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
                })
        }

        if !swiftDefines.isEmpty {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) \(swiftDefines)"
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

    // `nil` means settings without a condition
    private func settings(for platformName: String?) throws
        -> [PackageInfo.Target.TargetBuildSettingDescription.Setting]
    {
        settings.filter { setting in
            if let platformName, setting.hasConditions {
                let hasMacCatalystPlatform = setting.condition?.platformNames.contains("maccatalyst") == true
                let platformNames: [String]
                if hasMacCatalystPlatform {
                    platformNames = (setting.condition?.platformNames ?? []) + ["ios"]
                } else {
                    platformNames = setting.condition?.platformNames ?? []
                }
                return platformNames.contains(platformName)
            } else {
                return !setting.hasConditions
            }
        }
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
}
