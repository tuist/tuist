import Foundation
import TuistCore

/// Defines the interface to obtain the content to generate derived Info.plist files for the targets.
protocol InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - project: The project that hosts the target for which the Info.plist content will be returned
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(project: Project, target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]?
}

final class InfoPlistContentProvider: InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - project: The project that hosts the target for which the Info.plist content will be returned
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(project: Project, target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]? {
        if target.product == .staticLibrary || target.product == .dynamicLibrary {
            return nil
        }

        var content = base()

        // Bundle package type
        extend(&content, with: bundlePackageType(target))

        // Bundle Executable
        extend(&content, with: bundleExecutable(target))

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

        // watchOS app
        if target.product == .watch2App, target.platform == .watchOS {
            let host = hostTarget(for: target, in: project)
            extend(&content, with: watchosApp(name: target.name,
                                              hostAppBundleId: host?.bundleId))
        }

        // watchOS app extension
        if target.product == .watch2Extension, target.platform == .watchOS {
            let host = hostTarget(for: target, in: project)
            extend(&content, with: watchosAppExtension(name: target.name,
                                                       hostAppBundleId: host?.bundleId))
        }

        extend(&content, with: extendedWith.unwrappingValues())

        return content
    }

    /// Returns a dictionary that contains the base content that all Info.plist
    /// files should have regardless of the platform or product.
    ///
    /// - Returns: Base content.
    func base() -> [String: Any] {
        [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
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
        case .app, .appClips:
            packageType = "APPL"
        case .staticLibrary, .dynamicLibrary:
            packageType = nil
        case .uiTests, .unitTests, .bundle:
            packageType = "BNDL"
        case .staticFramework, .framework:
            packageType = "FMWK"
        case .watch2App, .watch2Extension:
            packageType = "$(PRODUCT_BUNDLE_PACKAGE_TYPE)"
        case .appExtension, .stickerPackExtension, .messagesExtension:
            packageType = "XPC!"
        }

        if let packageType = packageType {
            return ["CFBundlePackageType": packageType]
        } else {
            return [:]
        }
    }

    func bundleExecutable(_ target: Target) -> [String: Any] {
        let shouldIncludeBundleExecutableKey: (Target) -> Bool = {
            switch ($0.platform, $0.product) {
            case (.iOS, .bundle):
                return false
            default:
                return true
            }
        }

        if shouldIncludeBundleExecutableKey(target) {
            return [
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            ]
        } else {
            return [:]
        }
    }

    /// Returns the default Info.plist content that iOS apps should have.
    ///
    /// - Returns: Info.plist content.
    func iosApp() -> [String: Any] {
        [
            "LSRequiresIPhoneOS": true,
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
        [
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
        [
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
        ]
    }

    /// Returns the default Info.plist content for a watchOS App
    ///
    /// - Parameter hostAppBundleId: The host application's bundle identifier
    private func watchosApp(name: String, hostAppBundleId: String?) -> [String: Any] {
        var infoPlist: [String: Any] = [
            "CFBundleDisplayName": name,
            "WKWatchKitApp": true,
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
            ],
        ]
        if let hostAppBundleId = hostAppBundleId {
            infoPlist["WKCompanionAppBundleIdentifier"] = hostAppBundleId
        }
        return infoPlist
    }

    /// Returns the default Info.plist content for a watchOS App Extension
    ///
    /// - Parameter hostAppBundleId: The host application's bundle identifier
    private func watchosAppExtension(name: String, hostAppBundleId: String?) -> [String: Any] {
        let extensionAttributes: [String: Any] = hostAppBundleId.map { ["WKAppBundleIdentifier": $0] } ?? [:]
        return [
            "CFBundleDisplayName": name,
            "NSExtension": [
                "NSExtensionAttributes": extensionAttributes,
                "NSExtensionPointIdentifier": "com.apple.watchkit",
            ],
            "WKExtensionDelegateClassName": "$(PRODUCT_MODULE_NAME).ExtensionDelegate",
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

    private func hostTarget(for target: Target, in project: Project) -> Target? {
        project.targets.first {
            $0.dependencies.contains(.target(name: target.name))
        }
    }
}
