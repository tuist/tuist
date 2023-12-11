import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

/// Generate a new project using Tuist (suite 1)
final class GenerateOneAcceptanceTestiOSAppWithTests: TuistAcceptanceTestCase {
    func test_ios_app_with_tests() async throws {
        try setUpFixture("ios_app_with_tests")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateOneAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try setUpFixture("ios_app_with_frameworks")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsInfoPlistKey(
            "Framework1.framework",
            destination: "Debug-iphonesimulator",
            key: "Test"
        )
    }
}

final class GenerateOneAcceptanceTestiOSAppWithHeaders: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try setUpFixture("ios_app_with_headers")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class GenerateOneAcceptanceTestInvalidWorkspaceManifestName: TuistAcceptanceTestCase {
    func test_invalid_workspace_manifest_name() async throws {
        try setUpFixture("invalid_workspace_manifest_name")
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch {
            XCTAssertEqual(String(describing: error), "Manifest not found at path \(fixturePath.pathString)")
        }
    }
}

// TODO: Fix (this test has an issue in GitHub actions due to a missing tvOS platform)
// final class GenerateOneAcceptanceTestiOSAppWithSDK: TuistAcceptanceTestCase {
//    func test_ios_app_with_sdk() async throws {
//        try setUpFixture("ios_app_with_sdk")
//        try await run(GenerateCommand.self)
//        try await run(BuildCommand.self)
//        try await run(BuildCommand.self, "MacFramework", "--platform", "macOS")
//        try await run(BuildCommand.self, "TVFramework", "--platform", "tvOS")
//    }
// }

final class GenerateOneAcceptanceTestiOSAppWithFrameworkAndResources: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_and_resources() async throws {
        try setUpFixture("ios_app_with_framework_and_resources")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "tuist.png",
            "Examples/item.json",
            "Examples/list.json",
            "Assets.car",
            "resource.txt",
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
            "resource_without_extension",
            "StaticFrameworkResources.bundle",
            "StaticFramework2Resources.bundle",
            "StaticFramework3_StaticFramework3.bundle",
            "StaticFramework4_StaticFramework4.bundle",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        try await XCTAssertProductWithDestinationDoesNotContainResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "do_not_include.dat"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFrameworkResources.bundle",
            destination: "Debug-iphonesimulator",
            resource: "tuist-bundle.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework2Resources.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework2Resources-tuist.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework3_StaticFramework3.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework3Resources-tuist.png"
        )
        try await XCTAssertProductWithDestinationContainsResource(
            "StaticFramework4_StaticFramework4.bundle",
            destination: "Debug-iphonesimulator",
            resource: "StaticFramework4Resources-tuist.png"
        )
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "App", "Derived", "Sources"),
            [
                "TuistBundle+App.swift",
                "TuistStrings+App.swift",
                "TuistAssets+App.swift",
                "TuistFonts+App.swift",
                "TuistPlists+App.swift",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            fixturePath.appending(components: "StaticFramework3", "Derived", "Sources"),
            [
                "TuistAssets+StaticFramework3.swift",
                "TuistBundle+StaticFramework3.swift",
            ]
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
    }
}

final class GenerateOneAcceptanceTestIosAppWithCustomDevelopmentRegion: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_development_region() async throws {
        try setUpFixture("ios_app_with_custom_development_region")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }

        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let evening = AppStrings.tr("Greetings", "evening")
                """
            )
        )
    }
}

final class GenerateOneAcceptanceTestiOSAppWithCustomResourceParserOptions: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_resource_parser_options() async throws {
        try setUpFixture("ios_app_with_custom_resource_parser_options")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        for resource in [
            "en.lproj/Greetings.strings",
            "fr.lproj/Greetings.strings",
        ] {
            try await XCTAssertProductWithDestinationContainsResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }

        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let evening = AppStrings.tr("Greetings", "Good/evening")
                """
            )
        )
        XCTAssertTrue(
            try FileHandler.shared.readTextFile(
                fixturePath.appending(components: "Derived", "Sources", "TuistStrings+App.swift")
            )
            .contains(
                """
                public static let morning = AppStrings.tr("Greetings", "Good/morning")
                """
            )
        )
    }
}

final class GenerateOneAcceptanceTestiOSAppWithFrameworkLinkingStaticFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_framework_linking_static_framework() async throws {
        try setUpFixture("ios_app_with_framework_linking_static_framework")
        try await run(BuildCommand.self)

        try await XCTAssertProductWithDestinationContainsResource(
            "App.app",
            destination: "Debug-iphonesimulator",
            resource: "Frameworks/Framework1.framework/Framework1"
        )
        for resource in [
            "Frameworks/Framework2.framework/Framework2",
            "Frameworks/Framework3.framework/Framework3",
            "Frameworks/Framework4.framework/Framework4",
        ] {
            try await XCTAssertProductWithDestinationDoesNotContainResource(
                "App.app",
                destination: "Debug-iphonesimulator",
                resource: resource
            )
        }
        try XCTAssertProductWithDestinationDoesNotContainHeaders("App.app", destination: "Debug-iphonesimulator")
    }
}

final class GenerateOneAcceptanceTestsiOSAppWithCustomScheme: TuistAcceptanceTestCase {
    func test_ios_app_with_custom_scheme() async throws {
        try setUpFixture("ios_app_with_custom_scheme")
        try await run(BuildCommand.self)
        try await run(BuildCommand.self, "App-Debug")
        try await run(BuildCommand.self, "App-Release")
        try await run(BuildCommand.self, "App-Local")
    }
}

final class GenerateOneAcceptanceTestiOSAppWithLocalSwiftPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_local_swift_package() async throws {
        try setUpFixture("ios_app_with_local_swift_package")
        try await run(BuildCommand.self)
    }
}

final class GenerateOneAcceptanceTestiOSAppWithMultiConfigs: TuistAcceptanceTestCase {
    func test_ios_app_with_multi_configs() async throws {
        try setUpFixture("ios_app_with_multi_configs")
        try await run(GenerateCommand.self)
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Debug",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Debug"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Beta",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Beta"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "App",
            configuration: "Release",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Release"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Debug",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Debug"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Beta",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Target.Beta"
        )
        try await XCTAssertSchemeContainsBuildSettings(
            "Framework2",
            configuration: "Release",
            buildSettingKey: "CUSTOM_FLAG",
            buildSettingValue: "Release"
        )
    }
}

extension TuistAcceptanceTestCase {
    private func headers(
        for productName: String,
        destination: String
    ) throws -> [AbsolutePath] {
        let productPath = try productPath(for: productName, destination: destination)
        return FileHandler.shared.glob(productPath, glob: "**/*.h")
    }

    private func productPath(
        for name: String,
        destination: String
    ) throws -> AbsolutePath {
        try XCTUnwrap(
            FileHandler.shared.glob(derivedDataPath, glob: "**/Build/**/Products/\(destination)/\(name)/").first
        )
    }

    private func resourcePath(
        for productName: String,
        destination: String,
        resource: String
    ) throws -> AbsolutePath {
        let productPath = try productPath(for: productName, destination: destination)
        if let resource = FileHandler.shared.glob(productPath, glob: "**/\(resource)").first {
            return resource
        } else {
            XCTFail("Could not find resource \(resource) for product \(productName) and destination \(destination)")
            throw XCTUnwrapError.nilValueDetected
        }
    }

    func XCTAssertSchemeContainsBuildSettings(
        _ scheme: String,
        configuration: String,
        buildSettingKey: String,
        buildSettingValue: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let buildSettings = try await System.shared.runAndCollectOutput(
            [
                "/usr/bin/xcodebuild",
                "-scheme",
                scheme,
                "-workspace",
                workspacePath.pathString,
                "-configuration",
                configuration,
                "-showBuildSettings",
            ]
        )

        guard buildSettings.standardOutput.contains("\(buildSettingKey) = \"\(buildSettingValue)\"")
        else {
            XCTFail(
                "Couldn't find \(buildSettingKey) = \(buildSettingValue) for scheme \(scheme) and configuration \(configuration)",
                file: file,
                line: line
            )
            return
        }
    }

    func XCTAssertProductWithDestinationDoesNotContainHeaders(
        _ product: String,
        destination: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        if try !headers(for: product, destination: destination).isEmpty {
            XCTFail("Product with name \(product) and destination \(destination) contains headers", file: file, line: line)
        }
    }

    fileprivate func XCTAssertProductWithDestinationContainsResource(
        _ product: String,
        destination: String,
        resource: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let resourcePath = try resourcePath(
            for: product,
            destination: destination,
            resource: resource
        )

        if !FileHandler.shared.exists(resourcePath) {
            XCTFail(
                "Resource \(resource) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
        }
    }

    fileprivate func XCTAssertProductWithDestinationDoesNotContainResource(
        _ product: String,
        destination: String,
        resource: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(for: product, destination: destination)
        if !FileHandler.shared.glob(productPath, glob: "**/\(resource)").isEmpty {
            XCTFail("Resource \(resource) found for product \(product) and destination \(destination)", file: file, line: line)
        }
    }

    fileprivate func XCTAssertProductWithDestinationContainsInfoPlistKey(
        _ product: String,
        destination: String,
        key: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let infoPlistPath = try resourcePath(
            for: product,
            destination: destination,
            resource: "Info.plist"
        )
        let output = try await System.shared.runAndCollectOutput(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                "print :\(key)",
                infoPlistPath.pathString,
            ]
        )

        if output.standardOutput.isEmpty {
            XCTFail(
                "Key \(key) not found in the \(product) Info.plist",
                file: file,
                line: line
            )
        }
    }
}
