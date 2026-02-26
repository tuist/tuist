import Foundation
import Path
import XcodeGraph
@testable import XcodeProj

enum MockDefaults {
    static let defaultDebugSettings: [String: BuildSetting] = [
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.example.debug",
    ]

    static let defaultReleaseSettings: [String: BuildSetting] = [
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "VALIDATE_PRODUCT": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.example.release",
    ]

    nonisolated(unsafe) static let defaultProjectAttributes: [String: ProjectAttribute] = [
        "BuildIndependentTargetsInParallel": "YES",
    ]
}
