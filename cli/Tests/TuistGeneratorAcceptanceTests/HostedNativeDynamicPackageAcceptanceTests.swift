import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistGenerateCommand
import TuistProcess
import TuistTesting
import XcodeProj
@testable import TuistKit

struct HostedNativeDynamicPackageAcceptanceTests {
    @Test(.withFixture("generated_app_with_native_dynamic_package_hosted_tests"), .inTemporaryDirectory)
    func hostedTestsShareStaticStateAndLinkDynamicProducts() async throws {
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let resultPath = temporaryDirectory.appending(component: "HostedTests.xcresult")

        try await TuistTest.run(GenerateCommand.self, ["--path", fixturePath.pathString, "--no-open"])

        let project = try XcodeProj(pathString: fixturePath.appending(component: "HostedPackages.xcodeproj").pathString)
        let tests = try #require(project.pbxproj.nativeTargets.first { $0.name == "HostAppTests" })
        #expect(tests.packageProductDependencies?.map(\.productName).sorted() == [
            "AutomaticDynamicProduct", "DynamicProduct", "TestOnlyProduct",
        ])
        #expect(tests.embedFrameworksBuildPhases().flatMap { $0.files ?? [] }.isEmpty)

        try await CommandRunner().runAndWait(arguments: [
            "/usr/bin/xcodebuild", "test",
            "-workspace", fixturePath.appending(component: "HostedPackages.xcworkspace").pathString,
            "-scheme", "HostApp",
            "-only-testing:HostAppTests",
            "-destination", "platform=macOS",
            "-derivedDataPath", derivedDataPath.pathString,
            "-resultBundlePath", resultPath.pathString,
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        ])

        let resultJSON = try await CommandRunner().capture(arguments: [
            "/usr/bin/xcrun", "xcresulttool", "get", "test-results", "summary", "--path", resultPath.pathString,
        ])
        let summary = try JSONDecoder().decode(TestSummary.self, from: Data(resultJSON.utf8))
        #expect(summary.passedTests == 1)
        #expect(summary.failedTests == 0)

        let hostPath = derivedDataPath.appending(components: "Build", "Products", "Debug", "HostApp.app", "Contents")
        #expect(try await FileSystem().exists(hostPath.appending(components: "Frameworks", "DynamicProduct.framework")))
        #expect(try await !FileSystem().exists(hostPath.appending(
            components:
            "PlugIns",
            "HostAppTests.xctest",
            "Contents",
            "Frameworks",
            "DynamicProduct.framework"
        )))

        let objectsPath = derivedDataPath.appending(
            components:
            "Build",
            "Intermediates.noindex",
            "HostedPackages.build",
            "Debug",
            "HostAppTests.build",
            "Objects-normal"
        )
        let linkFileLists = try await FileSystem().glob(
            directory: objectsPath,
            include: ["*/HostAppTests.LinkFileList"]
        ).collect()
        try #require(!linkFileLists.isEmpty)
        for linkFileList in linkFileLists {
            let inputs = try await FileSystem().readTextFile(at: linkFileList)
            #expect(!inputs.contains("/StaticModule.o"))
            #expect(!inputs.contains("/AutomaticModule.o"))
            #expect(!inputs.contains("/PromotedModule.o"))
            #expect(inputs.contains("/TestOnlyModule.o"))
        }
    }

    private struct TestSummary: Decodable {
        let passedTests: Int
        let failedTests: Int
    }
}
