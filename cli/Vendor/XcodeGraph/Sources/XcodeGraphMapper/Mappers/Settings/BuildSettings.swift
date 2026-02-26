import Foundation
import XcodeProj

/// Keys representing various build settings that may appear in an Xcode project or workspace configuration.
enum BuildSettingKey: String {
    case sdkroot = "SDKROOT"
    case codeSignOnCopy = "CODE_SIGN_ON_COPY"
    case mergedBinaryType = "MERGED_BINARY_TYPE"
    case productBundleIdentifier = "PRODUCT_BUNDLE_IDENTIFIER"
    case infoPlistFile = "INFOPLIST_FILE"
    case codeSignEntitlements = "CODE_SIGN_ENTITLEMENTS"
    case iPhoneOSDeploymentTarget = "IPHONEOS_DEPLOYMENT_TARGET"
    case macOSDeploymentTarget = "MACOSX_DEPLOYMENT_TARGET"
    case watchOSDeploymentTarget = "WATCHOS_DEPLOYMENT_TARGET"
    case tvOSDeploymentTarget = "TVOS_DEPLOYMENT_TARGET"
    case visionOSDeploymentTarget = "VISIONOS_DEPLOYMENT_TARGET"
}

extension BuildSettings {
    subscript(_ key: BuildSettingKey) -> BuildSetting? {
        self[key.rawValue]
    }
}
