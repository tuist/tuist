import Foundation

/// Defines the interface to obtain the content to generate derived Info.plist files for the targets.
protocol InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]?
}

final class InfoPlistContentProvider: InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]? {
        if target.product == .staticLibrary || target.product == .dynamicLibrary {
            return nil
        }

        var content = base()

        // Bundle package type
        extend(&content, with: bundlePackageType(target))

        // iOS app
        if target.product == .app, target.platform == .iOS {
            extend(&content, with: iosApp())
        }

        // macOS app
        if target.product == .app, target.platform == .macOS {
            extend(&content, with: macosApp())
        }

        // macOS
        if target.platform == .macOS {
            extend(&content, with: macos())
        }

        extend(&content, with: extendedWith.unwrappingValues())

        return content
    }

    /// Returns a dictionary that contains the base content that all Info.plist
    /// files should have regardless of the platform or product.
    ///
    /// - Returns: Base content.
    func base() -> [String: Any] {
        return [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ]
    }

    /// Returns the Info.plist content that includes the CFBundlePackageType
    /// attribute depending on the target product type.
    ///
    /// - Parameter target: Target whose Info.plist's CFBundlePackageType will be returned.
    /// - Returns: Dictionary with the CFBundlePackageType attribute.
    func bundlePackageType(_ target: Target) -> [String: Any] {
        var packageType: String?

        switch target.product {
        case .app:
            packageType = "APPL"
        case .staticLibrary, .dynamicLibrary:
            packageType = nil
        case .uiTests, .unitTests, .bundle:
            packageType = "BNDL"
        case .staticFramework, .framework:
            packageType = "FMWK"
        case .appExtension, .stickerPackExtension:
            packageType = "XPC!"
        }

        if let packageType = packageType {
            return ["CFBundlePackageType": packageType]
        } else {
            return [:]
        }
    }

    /// Returns the default Info.plist content that iOS apps should have.
    ///
    /// - Returns: Info.plist content.
    func iosApp() -> [String: Any] {
        return [
            "LSRequiresIPhoneOS": true,
            "UILaunchStoryboardName": "LaunchScreen",
            "UIMainStoryboardFile": "Main",
            "UIRequiredDeviceCapabilities": [
                "armv7",
            ],
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
        ]
    }

    /// Returns the default Info.plist content that macOS apps should have.
    ///
    /// - Returns: Info.plist content.
    func macosApp() -> [String: Any] {
        return [
            "CFBundleIconFile": "",
            "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
            "NSMainStoryboardFile": "Main",
            "NSPrincipalClass": "NSApplication",
        ]
    }

    /// Returns the default Info.plist content that macOS targets should have.
    ///
    /// - Returns: Info.plist content.
    func macos() -> [String: Any] {
        return [
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
        ]
    }

    /// Given a dictionary, it extends it with another dictionary.
    ///
    /// - Parameters:
    ///   - base: Dictionary to be extended.
    ///   - with: The content to extend the dictionary with.
    fileprivate func extend(_ base: inout [String: Any], with: [String: Any]) {
        with.forEach { base[$0.key] = $0.value }
    }
}
