import Command
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
@testable import TuistSupport

struct SDKDeploymentTargetsProviderTests {
    private let commandRunner = MockCommandRunning()
    private let fileSystem = FileSystem()
    private let subject: SDKDeploymentTargetsProvider

    init() {
        subject = SDKDeploymentTargetsProvider(commandRunner: commandRunner)
    }

    @Test(.inTemporaryDirectory) func returns_the_minimum_deployment_target_of_every_sdk() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let minimums = [
            "iphoneos": "12.0",
            "macosx": "10.13",
            "watchos": "4.0",
            "appletvos": "12.0",
            "xros": "1.0",
        ]
        for (sdk, minimum) in minimums {
            try await stub(sdk: sdk, in: temporaryDirectory, settings: sdkSettings(sdk: sdk, minimum: minimum))
        }

        let got = await subject.minimumDeploymentTargets()

        #expect(
            got == SDKDeploymentTargets(iOS: "12.0", macOS: "10.13", watchOS: "4.0", tvOS: "12.0", visionOS: "1.0")
        )
    }

    @Test(.inTemporaryDirectory) func returns_the_mac_catalyst_minimum_of_the_macos_sdk() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await stub(
            sdk: "macosx",
            in: temporaryDirectory,
            settings: ["SupportedTargets": [
                "macosx": ["MinimumDeploymentTarget": "10.13"],
                "iosmac": ["MinimumDeploymentTarget": "13.1"],
            ]]
        )
        for sdk in ["iphoneos", "watchos", "appletvos", "xros"] {
            stubMissing(sdk: sdk)
        }

        let got = await subject.minimumDeploymentTargets()

        #expect(got == SDKDeploymentTargets(macOS: "10.13", macCatalyst: "13.1"))
    }

    @Test(.inTemporaryDirectory) func returns_nil_for_sdks_that_are_not_installed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await stub(sdk: "macosx", in: temporaryDirectory, settings: sdkSettings(sdk: "macosx", minimum: "12.0"))
        for sdk in ["iphoneos", "watchos", "appletvos", "xros"] {
            stubMissing(sdk: sdk)
        }

        let got = await subject.minimumDeploymentTargets()

        #expect(got == SDKDeploymentTargets(macOS: "12.0"))
    }

    @Test(.inTemporaryDirectory) func caches_the_deployment_targets() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        for sdk in ["iphoneos", "macosx", "watchos", "appletvos", "xros"] {
            try await stub(sdk: sdk, in: temporaryDirectory, settings: sdkSettings(sdk: sdk, minimum: "12.0"))
        }

        _ = await subject.minimumDeploymentTargets()
        _ = await subject.minimumDeploymentTargets()

        verify(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .called(5)
    }

    private func stubMissing(sdk: String) {
        given(commandRunner)
            .run(
                arguments: .value(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-path"]),
                environment: .any,
                workingDirectory: .any
            )
            .willProduce { _, _, _ in
                AsyncThrowingStream { $0.finish(throwing: TestError("\(sdk) is not installed")) }
            }
    }

    private func stub(sdk: String, in directory: AbsolutePath, settings: [String: Any]) async throws {
        let sdkPath = directory.appending(component: "\(sdk).sdk")
        try await fileSystem.makeDirectory(at: sdkPath)
        try PropertyListSerialization
            .data(fromPropertyList: settings, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: sdkPath.appending(component: "SDKSettings.plist").pathString))

        given(commandRunner)
            .run(
                arguments: .value(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-path"]),
                environment: .any,
                workingDirectory: .any
            )
            .willProduce { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.standardOutput(Array("\(sdkPath.pathString)\n".utf8)))
                    continuation.finish()
                }
            }
    }

    private func sdkSettings(sdk: String, minimum: String) -> [String: Any] {
        ["SupportedTargets": [sdk: ["MinimumDeploymentTarget": minimum, "DefaultDeploymentTarget": "26.5"]]]
    }
}

private struct TestError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
