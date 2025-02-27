import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ShareAcceptanceTests: ServerAcceptanceTestCase {
    func test_share_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(BuildCommand.self, "App")
            try await run(ShareCommand.self)
            let shareLink = try previewLink()
            try await run(RunCommand.self, shareLink, "-destination", "iPhone 16 Pro")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16 Pro")
            XCTAssertEqual(ServiceContext.current?.recordedUI(), """
            ▌ ✔ Success
            ▌ Successfully logged in.
            ▌ ✔ Success
            ▌ The project built successfully
            ▌ ✔ Success
            ▌ App was successfully launched 📲
            """)
        }
    }

    func test_share_ios_app_with_appclip() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithAppClip)
            try await run(BuildCommand.self)
            try await run(ShareCommand.self, "App")
            let shareLink = try previewLink("App")
            try await run(RunCommand.self, shareLink, "-destination", "iPhone 16")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16")
            XCTAssertEqual(ServiceContext.current?.recordedUI(), """
            ▌ ✔ Success
            ▌ Successfully logged in.
            ▌ ✔ Success
            ▌ The project built successfully
            ▌ ✔ Success
            ▌ App was successfully launched 📲
            """)
            ServiceContext.current?.flushRecordedUI()

            try await run(ShareCommand.self, "AppClip1")
            let appClipShareLink = try previewLink("AppClip1")
            try await run(RunCommand.self, appClipShareLink, "-destination", "iPhone 16")
            XCTAssertStandardOutput(pattern: "Installing and launching AppClip1 on iPhone 16")
            XCTAssertEqual(ServiceContext.current?.recordedUI(), """
            ▌ ✔ Success
            ▌ Successfully logged in.
            ▌ ✔ Success
            ▌ The project built successfully
            ▌ ✔ Success
            ▌ App was successfully launched 📲
            ▌ ✔ Success
            ▌ AppClip1 was successfully launched 📲
            """)
        }
    }

    func test_share_xcode_app() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.xcodeApp)
            try System.shared.runAndPrint(
                [
                    "/usr/bin/xcrun",
                    "xcodebuild",
                    "clean",
                    "build",
                    "-project",
                    fixturePath.appending(component: "App.xcodeproj").pathString,
                    "-scheme",
                    "App",
                    "-sdk",
                    "iphonesimulator",
                    "-derivedDataPath",
                    derivedDataPath.pathString,
                ]
            )
            try await run(ShareCommand.self, "App", "--platforms", "ios")
            try await run(RunCommand.self, try previewLink(), "-destination", "iPhone 16 Plus")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16 Plus")
            XCTAssertEqual(ServiceContext.current?.recordedUI(), """
            ▌ ✔ Success
            ▌ Successfully logged in.
            ▌ ✔ Success
            ▌ App was successfully launched 📲
            """)
        }
    }

    func test_share_xcode_app_files() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.xcodeApp)
            let buildDirectory = fixturePath.appending(component: "Build")
            try System.shared.runAndPrint(
                [
                    "/usr/bin/xcrun",
                    "xcodebuild",
                    "clean",
                    "build",
                    "-project",
                    fixturePath.appending(component: "App.xcodeproj").pathString,
                    "-scheme",
                    "App",
                    "-sdk",
                    "iphonesimulator",
                    "-derivedDataPath",
                    derivedDataPath.pathString,
                    "CONFIGURATION_BUILD_DIR=\(buildDirectory)",
                ]
            )

            // Testing sharing `.app` file directly
            try await run(
                ShareCommand.self,
                buildDirectory.appending(component: "App.app").pathString,
                "--platforms", "ios"
            )
            try await run(RunCommand.self, try previewLink(), "-destination", "iPhone 15 Pro Max")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 15 Pro Max")
            XCTAssertEqual(ServiceContext.current?.recordedUI(), """
            ▌ ✔ Success
            ▌ Successfully logged in.
            ▌ ✔ Success
            ▌ App was successfully launched 📲
            """)
        }
    }
}

extension ServerAcceptanceTestCase {
    fileprivate func previewLink(_ displayName: String = "App") throws -> String {
        try XCTUnwrap(
            ServiceContext.current?.testingLogHandler?.collected[.notice, >=]
                .components(separatedBy: .newlines)
                .first(where: { $0.contains("\(displayName) uploaded – share") })?
                .components(separatedBy: .whitespaces)
                .last
        )
    }
}
