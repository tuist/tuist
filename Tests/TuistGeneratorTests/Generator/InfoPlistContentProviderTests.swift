import Foundation
import XCTest

@testable import TuistGenerator

final class InfoPlistContentProviderTests: XCTestCase {
    var subject: InfoPlistContentProvider!

    override func setUp() {
        super.setUp()
        subject = InfoPlistContentProvider()
    }

    func test_content_wheniOSApp() {
        // Given
        let target = Target.test(platform: .iOS, product: .app)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        assertEqual(got, [
            "UISupportedInterfaceOrientations":
                ["UIInterfaceOrientationPortrait",
                 "UIInterfaceOrientationLandscapeLeft",
                 "UIInterfaceOrientationLandscapeRight"],
            "ExtraAttribute": "Value",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleIconFile": "",
            "CFBundleVersion": "1",
            "UIRequiredDeviceCapabilities": ["armv7"],
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "UIMainStoryboardFile": "Main",
            "CFBundleShortVersionString": "1.0",
            "LSRequiresIPhoneOS": true,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "NSMainStoryboardFile": "Main",
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
            "UILaunchStoryboardName": "LaunchScreen",
            "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
            "NSPrincipalClass": "NSApplication",
        ])
    }

    func test_content_whenMacosApp() {
        // Given
        let target = Target.test(platform: .macOS, product: .app)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        assertEqual(got, [
            "CFBundleShortVersionString": "1.0",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "ExtraAttribute": "Value",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ])
    }

    func test_content_whenMacosFramework() {
        // Given
        let target = Target.test(platform: .macOS, product: .framework)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        assertEqual(got, [
            "CFBundleShortVersionString": "1.0",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleVersion": "1",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "ExtraAttribute": "Value",
            "CFBundlePackageType": "FMWK",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleName": "$(PRODUCT_NAME)",
        ])
    }

    func test_content_whenMacosStaticLibrary() {
        // Given
        let target = Target.test(platform: .macOS, product: .staticLibrary)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        XCTAssertNil(got)
    }

    func test_content_whenMacosDynamicLibrary() {
        // Given
        let target = Target.test(platform: .macOS, product: .dynamicLibrary)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        XCTAssertNil(got)
    }

    func test_contentPackageType() {
        assertPackageType(subject.content(target: .test(product: .app), extendedWith: [:]), "APPL")
        assertPackageType(subject.content(target: .test(product: .unitTests), extendedWith: [:]), "BNDL")
        assertPackageType(subject.content(target: .test(product: .uiTests), extendedWith: [:]), "BNDL")
        assertPackageType(subject.content(target: .test(product: .bundle), extendedWith: [:]), "BNDL")
        assertPackageType(subject.content(target: .test(product: .framework), extendedWith: [:]), "FMWK")
        assertPackageType(subject.content(target: .test(product: .staticFramework), extendedWith: [:]), "FMWK")
    }

    fileprivate func assertPackageType(_ lhs: [String: Any]?,
                                       _ packageType: String?,
                                       file: StaticString = #file,
                                       line: UInt = #line) {
        let value = lhs?["CFBundlePackageType"] as? String

        if let packageType = packageType {
            XCTAssertEqual(value, packageType, "Expected package type \(packageType) but got \(value ?? "")", file: file, line: line)
        } else {
            XCTAssertNil(value, "Expected package type to be nil and got \(value ?? "")", file: file, line: line)
        }
    }

    fileprivate func assertEqual(_ lhs: [String: Any]?,
                                 _ rhs: [String: Any],
                                 file: StaticString = #file,
                                 line: UInt = #line) {
        let lhsNSDictionary = NSDictionary(dictionary: lhs ?? [:])
        let rhsNSDictionary = NSDictionary(dictionary: rhs)
        let message = """
        
        The dictionary:
        \(lhs ?? [:])
        
        Is not equal to the expected dictionary:
        \(rhs)
        """

        XCTAssertTrue(lhsNSDictionary.isEqual(rhsNSDictionary), message, file: file, line: line)
    }
}
