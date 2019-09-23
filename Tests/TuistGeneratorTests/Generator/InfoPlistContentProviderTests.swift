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
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "UIRequiredDeviceCapabilities": ["armv7"],
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ],
            "CFBundleShortVersionString": "1.0",
            "UIMainStoryboardFile": "Main",
            "LSRequiresIPhoneOS": true,
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "UILaunchStoryboardName": "LaunchScreen",
            "CFBundlePackageType": "APPL",
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ],
            "CFBundleVersion": "1",
            "ExtraAttribute": "Value",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleInfoDictionaryVersion": "6.0"
        ])
    }

    func test_content_whenMacosApp() {
        // Given
        let target = Target.test(platform: .macOS, product: .app)

        // When
        let got = subject.content(target: target, extendedWith: ["ExtraAttribute": "Value"])

        // Then
        assertEqual(got, [
            "CFBundleIconFile": "",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundlePackageType": "APPL",
            "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
            "NSMainStoryboardFile": "Main",
            "NSPrincipalClass": "NSApplication",
            "CFBundleShortVersionString": "1.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "1",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "ExtraAttribute": "Value",
            "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)"
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
