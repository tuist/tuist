import Foundation
import ServiceContextModule
import SnapshotTesting
import TuistAcceptanceTesting
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ShareAcceptanceTests: ServerAcceptanceTestCase {
    func test_share_ios_app_with_frameworks() async throws {
        try await ServiceContext.withTestingDependencies { @MainActor in
            try await setUpFixture(.iosAppWithFrameworks)

            // When: Build
            try await run(BuildCommand.self, "App")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
            ServiceContext.current?.resetRecordedUI()

            // When: Share
            try await run(ShareCommand.self)
            XCTAssertTrue(
                ServiceContext.current?.recordedUI()
                    .contains("Share App with others using the following link:") == true
            )
            let shareLink = try previewLink()
            ServiceContext.current?.resetRecordedUI()

            // When: Run
            try await run(RunCommand.self, shareLink, "-destination", "iPhone 16 Pro")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
            ServiceContext.current?.resetRecordedUI()
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16 Pro")
        }
    }

    func test_share_ios_app_with_appclip() async throws {
        try await ServiceContext.withTestingDependencies { @MainActor in
            try await setUpFixture(.iosAppWithAppClip)

            // When: Build
            try await run(BuildCommand.self)
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
            ServiceContext.current?.resetRecordedUI()

            // When: Share App
            try await run(ShareCommand.self, "App")
            let shareLink = try previewLink("App")
            XCTAssertTrue(
                ServiceContext.current?.recordedUI()
                    .contains("Share App with others using the following link:") == true
            )
            ServiceContext.current?.resetRecordedUI()

            // When: Run App on iPhone 16
            try await run(RunCommand.self, shareLink, "-destination", "iPhone 16")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
            ServiceContext.current?.resetRecordedUI()

            // When: Share AppClip1
            try await run(ShareCommand.self, "AppClip1")
            let appClipShareLink = try previewLink("AppClip1")
            XCTAssertTrue(
                ServiceContext.current?.recordedUI()
                    .contains("Share AppClip1 with others using the following link:") == true
            )
            ServiceContext.current?.resetRecordedUI()

            // When: Run AppClip1
            try await run(RunCommand.self, appClipShareLink, "-destination", "iPhone 16")
            XCTAssertStandardOutput(pattern: "Installing and launching AppClip1 on iPhone 16")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
        }
    }

    func test_share_xcode_app() async throws {
        try await ServiceContext.withTestingDependencies { @MainActor in
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
            XCTAssertTrue(
                ServiceContext.current?.recordedUI()
                    .contains("Share App with others using the following link:") == true
            )
            let previewLink = try previewLink()
            ServiceContext.current?.resetRecordedUI()

            try await run(RunCommand.self, previewLink, "-destination", "iPhone 16 Plus")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16 Plus")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
        }
    }

    func test_share_xcode_app_files() async throws {
        try await ServiceContext.withTestingDependencies { @MainActor in
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
            XCTAssertTrue(
                ServiceContext.current?.recordedUI()
                    .contains("Share App with others using the following link:") == true
            )
            let previewLink = try previewLink()
            ServiceContext.current?.resetRecordedUI()
            try await run(RunCommand.self, previewLink, "-destination", "iPhone 16 Plus")
            XCTAssertStandardOutput(pattern: "Installing and launching App on iPhone 16 Plus")
            assertSnapshot(of: ServiceContext.current?.recordedUI() ?? "", as: .lines)
        }
    }
}

extension ServerAcceptanceTestCase {
    fileprivate func previewLink(_ displayName: String = "App") throws -> String {
        try XCTUnwrap(
            ServiceContext.current?.recordedUI()?
                .components(separatedBy: .newlines)
                .first(where: { $0.contains("Share \(displayName) with others") })?
                .components(separatedBy: .whitespaces)
                .last
        )
    }
}
