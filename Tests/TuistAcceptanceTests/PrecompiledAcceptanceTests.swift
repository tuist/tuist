import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class PrecomiledAcceptanceTestiOSAppWithStaticFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_static_frameworks() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithStaticFrameworks)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
    }
}

final class PrecomiledAcceptanceTestiOSAppWithStaticLibraries: TuistAcceptanceTestCase {
    func test_ios_app_with_static_libraries() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithStaticLibraries)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
    }
}

final class PrecomiledAcceptanceTestiOSAppWithTransitiveFramework: TuistAcceptanceTestCase {
    func test_ios_app_with_transitive_framework() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithTransitiveFramework)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", "--platform", "iOS", context: context)
        try await XCTAssertProductWithDestinationContainsFrameworkWithArchitecture(
            framework: "Framework1",
            architecture: "arm64"
        )
        try XCTAssertProductWithDestinationDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try await run(BuildCommand.self, "Framework1-iOS", "--platform", "iOS", context: context)
        try await run(BuildCommand.self, "Framework1-macOS", "--platform", "macOS", context: context)
        try await run(BuildCommand.self, "Framework1Tests-iOS", "--platform", "iOS", context: context)
        try await run(BuildCommand.self, "Framework1Tests-macOS", "--platform", "macOS", context: context)
        try await run(BuildCommand.self, "StaticFramework1", "--platform", "iOS", context: context)
    }
}

final class PrecompiledAcceptanceTestiOSAppWithStaticLibraryAndPackage: TuistAcceptanceTestCase {
    func test_ios_app_with_static_library_and_package() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithStaticLibraryAndPackage)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
    }
}

final class PrecompiledAcceptanceTestiOSAppWithXCFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_xcframeworks() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithXcframeworks)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
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
