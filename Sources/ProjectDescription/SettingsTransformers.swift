import Foundation

extension Dictionary {
    mutating func merge(with dict: [Key: Value]) {
        dict.forEach { self[$0.key] = $0.value }
    }

    func merging(with dict: [Key: Value]) -> Dictionary {
        var copy = self
        copy.merge(with: dict)
        return copy
    }
}

private extension Bool {
    var asSettingValue: SettingValue {
        self ? "YES" : "NO"
    }
}

private extension String {
    var asSettingValue: SettingValue {
        .init(stringLiteral: self)
    }
}

public enum SwiftCompilationMode: String {
    case singlefile
    case wholemodule
}

public enum SwiftOptimizationLevel: String {
    case o = "-O"
    case oNone = "-Onone"
    case oSize = "-Osize"
}

public extension SettingsDictionary {
    // MARK: - Deployment target and SDKROOT

    /// Sets "IPHONEOS_DEPLOYMENT_TARGET" to `value`
    func iPhoneOSDeploymentTarget(_ value: String) -> SettingsDictionary {
        merging(with: ["IPHONEOS_DEPLOYMENT_TARGET": value.asSettingValue])
    }

    /// Sets "SDKROOT" to "iphoneos"
    func iPhoneOSasSDKRoot() -> SettingsDictionary {
        merging(with: ["SDKROOT": "iphoneos"])
    }

    /// Sets "SDKROOT" to `value`
    func sdkRoot(_ value: String) -> SettingsDictionary {
        merging(with: ["SDKROOT": value.asSettingValue])
    }

    // MARK: - Code signing

    /// Sets "CODE_SIGN_STYLE" to "Manual"
    func manualCodeSigning() -> SettingsDictionary {
        merging(with: ["CODE_SIGN_STYLE": "Manual"])
    }

    /// Sets "CODE_SIGN_STYLE" to "Automatic" and "DEVELOPMENT_TEAM" to `devTeam`
    func automaticCodeSigning(devTeam: String) -> SettingsDictionary {
        merging(with: [
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": devTeam.asSettingValue
        ])
    }

    ///Sets "CODE_SIGN_IDENTITY" to "Apple Development"
    func codeSignIdentityAppleDevelopment() -> SettingsDictionary {
        codeSignIdentity("Apple Development")
    }

    ///Sets "CODE_SIGN_IDENTITY" to `identity`
    func codeSignIdentity(_ identity: String) -> SettingsDictionary {
        merging(with: ["CODE_SIGN_IDENTITY": identity.asSettingValue])
    }

    // MARK: - Versioning and Product Name

    ///Sets "PRODUCT_NAME" to `name`
    func productName(_ name: String) -> SettingsDictionary {
        merging(with: ["PRODUCT_NAME": name.asSettingValue])
    }

    /// Sets "CURRENT_PROJECT_VERSION" to `version`
    func currentProjectVersion(_ version: String) -> SettingsDictionary {
        merging(with: ["CURRENT_PROJECT_VERSION": version.asSettingValue])
    }

    /// Sets "VERSIONING_SYSTEM" to "apple-generic"
    func appleGenericVersioningSystem() -> SettingsDictionary {
        merging(with: ["VERSIONING_SYSTEM": "apple-generic"])
    }

    /// Sets "VERSION_INFO_PREFIX" to `version`. If prefix is not `nil`, it's used as "VERSION_INFO_PREFIX"; and suffix as "VERSION_INFO_SUFFIX"
    func versionInfo(_ version: String, prefix: String? = nil, suffix: String? = nil) -> SettingsDictionary {
        var versionSettings: [String: SettingValue] = ["VERSION_INFO_STRING": version.asSettingValue]
        versionSettings["VERSION_INFO_PREFIX"] = prefix?.asSettingValue
        versionSettings["VERSION_INFO_SUFFIX"] = suffix?.asSettingValue

        return merging(with: versionSettings)
    }

    // MARK: - Swift Settings

    ///Sets "SWIFT_VERSION" to `version`
    func swiftVersion(_ version: String) -> SettingsDictionary {
        merging(with: ["SWIFT_VERSION": version.asSettingValue])
    }

    ///Sets "OTHER_SWIFT_FLAGS" to `flags`
    func otherSwiftFlags(_ flags: String) -> SettingsDictionary {
        merging(with: ["OTHER_SWIFT_FLAGS": flags.asSettingValue])
    }

    /// Sets "SWIFT_COMPILATION_MODE" to the available `SwiftCompilationMode` ("singlefile" or "wholemodule")
    func swiftCompilationMode(_ mode: SwiftCompilationMode) -> SettingsDictionary {
        merging(with: ["SWIFT_COMPILATION_MODE": mode.rawValue.asSettingValue])
    }

    /// Sets "SWIFT_OPTIMIZATION_LEVEL" to the available `SwiftOptimizationLevel` ("-O", "-Onone" or "-Osize")
    func swiftOptimizationLevel(_ level: SwiftOptimizationLevel) -> SettingsDictionary {
        merging(with: ["SWIFT_OPTIMIZATION_LEVEL": level.rawValue.asSettingValue])
    }

    // MARK: - Bitcode

    ///Sets "ENABLE_BITCODE" to "YES" or "NO"
    func bitcodeEnabled(_ enabled: Bool) -> SettingsDictionary {
        merging(with: ["ENABLE_BITCODE": enabled.asSettingValue])
    }

    // MARK: - Catalyst

    ///Sets "SUPPORTS_MACCATALYST" to "YES" or "NO"
    func supportsMacCatalist(_ enabled: Bool) -> SettingsDictionary {
        merging(with: ["SUPPORTS_MACCATALYST": enabled.asSettingValue])
    }

    ///Sets "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER" to "YES" or "NO"
    func deriveMacCatalystProductBundleId(_ enabled: Bool) -> SettingsDictionary {
        merging(with: ["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": enabled.asSettingValue])
    }
}
