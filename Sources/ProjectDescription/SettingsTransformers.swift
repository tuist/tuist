import Foundation

public extension SettingsDictionary {
    mutating func merge(_ other: SettingsDictionary) {
        merge(other) { $1 }
    }

    func merging(_ other: SettingsDictionary) -> SettingsDictionary {
        merging(other) { $1 }
    }
}

private extension SettingValue {
    init(_ string: String) {
        self = .init(stringLiteral: string)
    }

    init(_ bool: Bool) {
        self = .init(booleanLiteral: bool)
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

    /// Sets "SDKROOT" to `value`
    func sdkRoot(_ value: String) -> SettingsDictionary {
        merging(["SDKROOT": SettingValue(value)])
    }

    // MARK: - Code signing

    /// Sets "CODE_SIGN_STYLE" to "Manual"
    func manualCodeSigning(identity: String? = nil, provisioningProfileSpecifier: String? = nil) -> SettingsDictionary {
        var manualCodeSigning: SettingsDictionary = ["CODE_SIGN_STYLE": "Manual"]
        manualCodeSigning["PROVISIONING_PROFILE_SPECIFIER"] = provisioningProfileSpecifier.map { SettingValue($0) }

        let merged = merging(manualCodeSigning)

        guard let identity = identity else {
            return merged
        }

        return merged.codeSignIdentity(identity)
    }

    /// Sets "CODE_SIGN_STYLE" to "Automatic" and "DEVELOPMENT_TEAM" to `devTeam`
    func automaticCodeSigning(devTeam: String) -> SettingsDictionary {
        merging([
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": SettingValue(devTeam),
        ])
    }

    /// Sets "CODE_SIGN_IDENTITY" to "Apple Development"
    func codeSignIdentityAppleDevelopment() -> SettingsDictionary {
        codeSignIdentity("Apple Development")
    }

    /// Sets "CODE_SIGN_IDENTITY" to `identity`
    func codeSignIdentity(_ identity: String) -> SettingsDictionary {
        merging(["CODE_SIGN_IDENTITY": SettingValue(identity)])
    }

    // MARK: - Versioning and Product Name

    /// Sets "PRODUCT_NAME" to `name`
    func productName(_ name: String) -> SettingsDictionary {
        merging(["PRODUCT_NAME": SettingValue(name)])
    }

    /// Sets "CURRENT_PROJECT_VERSION" to `version`
    func currentProjectVersion(_ version: String) -> SettingsDictionary {
        merging(["CURRENT_PROJECT_VERSION": SettingValue(version)])
    }

    /// Sets "VERSIONING_SYSTEM" to "apple-generic"
    func appleGenericVersioningSystem() -> SettingsDictionary {
        merging(["VERSIONING_SYSTEM": "apple-generic"])
    }

    /// Sets "VERSION_INFO_PREFIX" to `version`. If prefix is not `nil`, it's used as "VERSION_INFO_PREFIX"; and suffix as "VERSION_INFO_SUFFIX"
    func versionInfo(_ version: String, prefix: String? = nil, suffix: String? = nil) -> SettingsDictionary {
        var versionSettings: SettingsDictionary = ["VERSION_INFO_STRING": SettingValue(version)]
        versionSettings["VERSION_INFO_PREFIX"] = prefix.map { SettingValue($0) }
        versionSettings["VERSION_INFO_SUFFIX"] = suffix.map { SettingValue($0) }

        return merging(versionSettings)
    }

    // MARK: - Swift Settings

    /// Sets "SWIFT_VERSION" to `version`
    func swiftVersion(_ version: String) -> SettingsDictionary {
        merging(["SWIFT_VERSION": SettingValue(version)])
    }

    /// Sets "OTHER_SWIFT_FLAGS" to `flags`
    func otherSwiftFlags(_ flags: String...) -> SettingsDictionary {
        merging(["OTHER_SWIFT_FLAGS": SettingValue(flags.joined(separator: " "))])
    }

    /// Sets "SWIFT_COMPILATION_MODE" to the available `SwiftCompilationMode` ("singlefile" or "wholemodule")
    func swiftCompilationMode(_ mode: SwiftCompilationMode) -> SettingsDictionary {
        merging(["SWIFT_COMPILATION_MODE": SettingValue(mode)])
    }

    /// Sets "SWIFT_OPTIMIZATION_LEVEL" to the available `SwiftOptimizationLevel` ("-O", "-Onone" or "-Osize")
    func swiftOptimizationLevel(_ level: SwiftOptimizationLevel) -> SettingsDictionary {
        merging(["SWIFT_OPTIMIZATION_LEVEL": SettingValue(level)])
    }

    // MARK: - Bitcode

    /// Sets "ENABLE_BITCODE" to "YES" or "NO"
    func bitcodeEnabled(_ enabled: Bool) -> SettingsDictionary {
        merging(["ENABLE_BITCODE": SettingValue(enabled)])
    }

    // MARK: - Catalyst

    /// Sets "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER" to "YES" or "NO"
    func deriveMacCatalystProductBundleId(_ enabled: Bool) -> SettingsDictionary {
        merging(["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": SettingValue(enabled)])
    }
}
