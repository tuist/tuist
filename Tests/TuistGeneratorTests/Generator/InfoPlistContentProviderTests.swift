import Foundation
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import XCTest
@testable import TuistGenerator

final class InfoPlistContentProviderTests: XCTestCase {
    var subject: InfoPlistContentProvider!

    override func setUp() {
        super.setUp()
        subject = InfoPlistContentProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_content_wheniOSApp_withiPadSupport() {
        // Given
        let target = Target.test(
            platform: .iOS,
            product: .app,
            deploymentTarget: .iOS("16.0", [.iphone, .ipad], supportsMacDesignedForIOS: true)
        )

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

        // Then
        assertEqual(got, [
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "UIRequiredDeviceCapabilities": ["armv7"],
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
            "CFBundleShortVersionString": "1.0",
            "LSRequiresIPhoneOS": true,
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundlePackageType": "APPL",
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
            "CFBundleVersion": "1",
            "ExtraAttribute": "Value",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "UIApplicationSceneManifest": [
                "UIApplicationSupportsMultipleScenes": false,
                "UISceneConfigurations": [:],
            ],
        ])
    }

    func test_content_wheniOSApp_withoutiPadSupport() {
        // Given
        let target = Target.test(
            platform: .iOS,
            product: .app,
            deploymentTarget: .iOS("16.0", .iphone, supportsMacDesignedForIOS: true)
        )

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

        // Then
        assertEqual(got, [
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "UIRequiredDeviceCapabilities": ["armv7"],
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
            "CFBundleShortVersionString": "1.0",
            "LSRequiresIPhoneOS": true,
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "ExtraAttribute": "Value",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "UIApplicationSceneManifest": [
                "UIApplicationSupportsMultipleScenes": false,
                "UISceneConfigurations": [:],
            ],
        ])
    }

    func test_content_whenMacosApp() {
        // Given
        let target = Target.test(platform: .macOS, product: .app)

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

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
            "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
        ])
    }

    func test_content_whenMacosFramework() {
        // Given
        let target = Target.test(platform: .macOS, product: .framework)

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

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
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

        // Then
        XCTAssertNil(got)
    }

    func test_content_whenMacosDynamicLibrary() {
        // Given
        let target = Target.test(platform: .macOS, product: .dynamicLibrary)

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

        // Then
        XCTAssertNil(got)
    }

    func test_content_wheniOSResourceBundle() {
        // Given
        let target = Target.test(platform: .iOS, product: .bundle)

        // When
        let got = subject.content(
            project: .empty(),
            target: target,
            extendedWith: ["ExtraAttribute": "Value"]
        )

        // Then
        assertEqual(got, [
            "CFBundlePackageType": "BNDL",
            "ExtraAttribute": "Value",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
        ])
    }

    func test_contentPackageType() {
        func content(for target: Target) -> [String: Any]? {
            subject.content(
                project: .empty(),
                target: target,
                extendedWith: [:]
            )
        }

        assertPackageType(content(for: .test(product: .app)), "APPL")
        assertPackageType(content(for: .test(product: .unitTests)), "BNDL")
        assertPackageType(content(for: .test(product: .uiTests)), "BNDL")
        assertPackageType(content(for: .test(product: .bundle)), "BNDL")
        assertPackageType(content(for: .test(product: .framework)), "FMWK")
        assertPackageType(content(for: .test(product: .staticFramework)), "FMWK")
        assertPackageType(content(for: .test(product: .watch2App)), "$(PRODUCT_BUNDLE_PACKAGE_TYPE)")
        assertPackageType(content(for: .test(product: .appClip)), "APPL")
    }

    func test_content_whenWatchOSApp() {
        // Given
        let watchApp = Target.test(
            name: "MyWatchApp",
            platform: .watchOS,
            product: .watch2App
        )
        let app = Target.test(
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.my.app.id",
            dependencies: [
                .target(name: watchApp.name),
            ]
        )
        let project = Project.test(targets: [
            app,
            watchApp,
        ])

        // When
        let got = subject.content(
            project: project,
            target: watchApp,
            extendedWith: [
                "ExtraAttribute": "Value",
            ]
        )

        // Then
        assertEqual(got, [
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
            ],
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "1",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleDisplayName": "MyWatchApp",
            "WKWatchKitApp": true,
            "WKCompanionAppBundleIdentifier": "io.tuist.my.app.id",
            "ExtraAttribute": "Value",

        ])
    }

    func test_content_whenWatchOSAppExtension() {
        // Given
        let watchAppExtension = Target.test(
            name: "MyWatchAppExtension",
            platform: .watchOS,
            product: .watch2Extension
        )
        let watchApp = Target.test(
            platform: .watchOS,
            product: .watch2App,
            bundleId: "io.tuist.my.app.id.mywatchapp",
            dependencies: [
                .target(name: watchAppExtension.name),
            ]
        )
        let project = Project.test(targets: [
            watchApp,
            watchAppExtension,
        ])

        // When
        let got = subject.content(
            project: project,
            target: watchAppExtension,
            extendedWith: [
                "ExtraAttribute": "Value",
            ]
        )

        // Then
        assertEqual(got, [
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "1",
            "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleDisplayName": "MyWatchAppExtension",
            "NSExtension": [
                "NSExtensionAttributes": [
                    "WKAppBundleIdentifier": "io.tuist.my.app.id.mywatchapp",
                ],
                "NSExtensionPointIdentifier": "com.apple.watchkit",
            ],
            "WKExtensionDelegateClassName": "$(PRODUCT_MODULE_NAME).ExtensionDelegate",
            "ExtraAttribute": "Value",
        ])
    }

    // MARK: - Helpers

    fileprivate func assertPackageType(
        _ lhs: [String: Any]?,
        _ packageType: String?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let value = lhs?["CFBundlePackageType"] as? String

        if let packageType = packageType {
            XCTAssertEqual(
                value,
                packageType,
                "Expected package type \(packageType) but got \(value ?? "")",
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(value, "Expected package type to be nil and got \(value ?? "")", file: file, line: line)
        }
    }

    fileprivate func assertEqual(
        _ lhs: [String: Any]?,
        _ rhs: [String: Any],
        file: StaticString = #file,
        line: UInt = #line
    ) {
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
