import Foundation
import MockableTest
import Path
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistAutomation

final class AppBundleServiceTests: TuistUnitTestCase {
    private var subject: AppBundleService!

    override func setUp() {
        super.setUp()

        subject = AppBundleService(fileHandler: fileHandler)
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_read_app_bundle() throws {
        // Given
        let appBundlePath = fixturePath(path: try RelativePath(validating: "App.app"))

        // When
        let appBundle = try subject.read(appBundlePath)

        // Then
        XCTAssertEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: Version("1.0"),
                    name: "App",
                    bundleId: "io.tuist.App",
                    minimumOSVersion: Version("17.4"),
                    supportedPlatforms: [.simulator(.iOS)]
                )
            )
        )
    }

    func test_read_bundle_when_does_not_exist() throws {
        // Given
        let appBundlePath = try temporaryPath()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.read(appBundlePath),
            AppBundleServiceError.missingInfoPlist(appBundlePath.appending(component: "Info.plist"))
        )
    }
}
