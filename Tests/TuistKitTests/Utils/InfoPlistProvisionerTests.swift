import Basic
import Foundation
import XCTest
@testable import TuistKit

final class InfoPlistProvisionerTests: XCTestCase {
    var subject: InfoPlistProvisioner!
    var tmpDir: TemporaryDirectory!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        subject = InfoPlistProvisioner()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        path = tmpDir.path.appending(component: "Info.plist")
    }

    func test_generate_when_ios_app() throws {
        let got = try provision(platform: .iOS, product: .app)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
            "LSRequiresIPhoneOS": true,
            "UIRequiredDeviceCapabilities": ["armv7"],
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
            "UILaunchStoryboardName": "Launch Screen",
            "UIMainStoryboardFile": "Main",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func test_generate_when_tvos_app() throws {
        let got = try provision(platform: .tvOS, product: .app)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
            "LSRequiresIPhoneOS": true,
            "UIRequiredDeviceCapabilities": ["arm64"],
            "UIMainStoryboardFile": "Main",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func test_generate_when_macos_app() throws {
        let got = try provision(platform: .macOS, product: .app)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
            "NSPrincipalClass": "NSApplication",
            "CFBundleIconFile": "",
            "NSMainStoryboardFile": "Main",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func test_generate_when_macos_framework() throws {
        let got = try provision(platform: .macOS, product: .framework)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "CFBundlePackageType": "FMWK",
            "NSPrincipalClass": "",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func test_generate_when_ios_framework() throws {
        let got = try provision(platform: .iOS, product: .framework)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "CFBundlePackageType": "FMWK",
            "NSPrincipalClass": "",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func test_generate_when_tvos_framework() throws {
        let got = try provision(platform: .tvOS, product: .framework)
        let expected: [String: Any] = [
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "CFBundlePackageType": "FMWK",
            "NSPrincipalClass": "",
        ]
        XCTAssertEqual(NSDictionary(dictionary: got),
                       NSDictionary(dictionary: expected))
    }

    func provision(platform: Platform, product: Product) throws -> [String: AnyHashable] {
        try subject.generate(path: path, platform: platform, product: product)
        let data = try Data(contentsOf: path.url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (object as? [String: AnyHashable]) ?? [:]
    }
}
