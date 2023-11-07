import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

/// Generate a new project using Tuist (suite 1)
 final class GenerateOneAcceptanceTestiOSAppWithTests: TuistAcceptanceTestCase {
    func test_ios_app_with_tests() async throws {
        try setUpFixture("ios_app_with_tests")
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
        try await run(TestCommand.self)
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
    func test() async throws {
        try setUpFixture("invalid_workspace_manifest_name")
        do {
            try await run(GenerateCommand.self)
            XCTFail("Generate command should have failed")
        } catch let error as FatalError {
            XCTAssertEqual(error.description, "Manifest not found at path \(fixturePath.pathString)")
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
    }
}

extension TuistAcceptanceTestCase {
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
        return try XCTUnwrap(
            FileHandler.shared.glob(productPath, glob: "**/\(resource)").first
        )
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
