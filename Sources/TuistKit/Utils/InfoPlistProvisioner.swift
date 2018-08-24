import Basic
import Foundation
import TuistCore

protocol InfoPlistProvisioning: AnyObject {
    func generate(path: AbsolutePath, platform: Platform, product: Product) throws
}

/// Creates a base Info.plist. This is intended to be used from the init command.
class InfoPlistProvisioner: InfoPlistProvisioning {

    // MARK: - Attributes

    /// File handler.
    private let fileHandler: FileHandling

    /// Initializes the provisioner with its attributes.
    ///
    /// - Parameter fileHandler: file handler.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Generates the Info.plist at the given path.
    ///
    /// - Parameters:
    ///   - path: the absolute path to the file (/path/to/Info.plist)
    ///   - platform: platform of the target the Info.plist file will be generated for.
    ///   - product: type of product of the target the Info.plist will be generated for.
    /// - Throws: an error if the Info.plist file cannot be generated.
    func generate(path: AbsolutePath, platform: Platform, product: Product) throws {
        let dictinary = base(platform: platform, product: product)
        let data = try PropertyListSerialization.data(fromPropertyList: dictinary, format: .xml, options: 0)
        try data.write(to: path.url)
    }

    /// Gets the base Info.plist content for the given platform and product.
    ///
    /// - Parameters:
    ///   - platform: platform of the target the Info.plist file will be generated for.
    ///   - product: type of product of the target the Info.plist will be generated for.
    /// - Returns: base Info.plist content.
    fileprivate func base(platform: Platform, product: Product) -> [String: Any] {
        var base: [String: Any] = [:]
        base["CFBundleDevelopmentRegion"] = "$(DEVELOPMENT_LANGUAGE)"
        base["CFBundleExecutable"] = "$(EXECUTABLE_NAME)"
        base["CFBundleIdentifier"] = "$(PRODUCT_BUNDLE_IDENTIFIER)"
        base["CFBundleInfoDictionaryVersion"] = "6.0"
        base["CFBundleName"] = "$(PRODUCT_NAME)"
        base["CFBundleShortVersionString"] = "1.0"
        base["NSHumanReadableCopyright"] = "Copyright ©. All rights reserved."

        // Application
        if product == .app {
            base["CFBundleVersion"] = "1"
            base["CFBundlePackageType"] = "APPL"

            // Framework
        } else if product == .framework {
            base["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
            base["CFBundlePackageType"] = "FMWK"
            base["NSPrincipalClass"] = ""

            // Tests bundle
        } else if product == .unitTests || product == .uiTests {
            base["CFBundleVersion"] = "1"
            base["CFBundlePackageType"] = "BNDL"
        }

        // macOS application
        if product == .app && platform == .macOS {
            base["LSMinimumSystemVersion"] = "$(MACOSX_DEPLOYMENT_TARGET)"
            base["NSPrincipalClass"] = "NSApplication"
            base["CFBundleIconFile"] = ""
        }

        // iOS application
        if product == .app && platform == .iOS {
            base["LSRequiresIPhoneOS"] = true
            base["UIRequiredDeviceCapabilities"] = ["armv7"]
            base["UISupportedInterfaceOrientations"] = [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ]
            base["UISupportedInterfaceOrientations~ipad"] = [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ]
        }
        
        // tvOS application
        if product == .app && platform == .tvOS {
            base["LSRequiresIPhoneOS"] = true
            base["UIRequiredDeviceCapabilities"] = ["arm64"]
        }
        
        return base
    }
}
