import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class PrecomiledAcceptanceTestiOSAppWithStaticFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_static_frameworks() async throws {
        try setUpFixture("ios_app_with_static_frameworks")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class PrecomiledAcceptanceTestiOSAppWithStaticLibraries: TuistAcceptanceTestCase {
    func test_ios_app_with_static_libraries() async throws {
        try setUpFixture("ios_app_with_static_libraries")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class PrecomiledAcceptanceTestiOSAppWithTransitiveFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_transitive_framework() async throws {
        try setUpFixture("ios_app_with_transitive_framework")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "iOS")
        try await XCTAssertProductWithDestinationContainsFrameworkWithArchitecture(
            framework: "Framework1",
            architecture: "x86_64"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try await run(BuildCommand.self, "Framework1-iOS", "--platform", "iOS")
        try await run(BuildCommand.self, "Framework1-macOS", "--platform", "macOS")
        try await run(BuildCommand.self, "Framework1Tests-iOS", "--platform", "iOS")
        try await run(BuildCommand.self, "Framework1Tests-macOS", "--platform", "macOS")
        try await run(BuildCommand.self, "StaticFramework1", "--platform", "iOS")
    }
}

final class PrecompiledAcceptanceTestiOSAppWithStaticLibraryAndPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_static_library_and_package() async throws {
        try setUpFixture("ios_app_with_static_library_and_package")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class PrecompiledAcceptanceTestiOSAppWithXCFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_xcframeworks() async throws {
        try setUpFixture("ios_app_with_xcframeworks")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await XCTAssertProductWithDestinationContainsFrameworkWithArchitecture(
            framework: "MyFramework",
            architecture: "x86_64"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
    }
}

extension TuistAcceptanceTestCase {
    func XCTAssertProductWithDestinationContainsFrameworkWithArchitecture(
        _ product: String = "App.app",
        destination: String = "Debug-iphonesimulator",
        framework: String,
        architecture: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let productPath = try productPath(
            for: product,
            destination: destination
        )

        guard let frameworkPath = FileHandler.shared.glob(productPath, glob: "**/Frameworks/\(framework).framework").first,
              FileHandler.shared.exists(frameworkPath)
        else {
            XCTFail(
                "Framework \(framework) not found for product \(product) and destination \(destination)",
                file: file,
                line: line
            )
            return
        }

        let fileInfo = try await System.shared.runAndCollectOutput(
            [
                "file",
                frameworkPath.appending(component: framework).pathString,
            ]
        )
        XCTAssertTrue(fileInfo.standardOutput.contains(architecture))
    }
}

//Scenario: The project is an iOS application with a target dependency and transitive framework dependency (ios_app_with_transitive_framework)
//  Given that tuist is available
//  And I have a working directory
//  Then I copy the fixture ios_app_with_transitive_framework into the working directory
//  Then tuist generates the project
//  Then I should be able to build for iOS the scheme App
//  Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'Framework1' with architecture 'x86_64'
//  Then the product 'App.app' with destination 'Debug-iphonesimulator' contains the framework 'Framework2' without architecture 'arm64'
//  Then the product 'App.app' with destination 'Debug-iphonesimulator' does not contain headers
//  Then I should be able to build for iOS the scheme App
//  Then the product 'AppUITests-Runner.app' with destination 'Debug-iphonesimulator' does not contain the framework 'Framework2'
//  Then I should be able to build for iOS the scheme Framework1-iOS
//  Then I should be able to build for macOS the scheme Framework1-macOS
//  Then I should be able to build for iOS the scheme Framework1Tests-iOS
//  Then I should be able to build for macOS the scheme Framework1Tests-macOS
//  Then I should be able to build for iOS the scheme StaticFramework1
