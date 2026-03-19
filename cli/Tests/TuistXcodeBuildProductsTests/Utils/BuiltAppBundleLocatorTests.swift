import FileSystem
import Mockable
import Path
import TuistSimulator
import TuistTesting
import TuistXcodeBuildProducts
import XcodeGraph
import XCTest

@testable import TuistXcodeBuildProducts

final class BuiltAppBundleLocatorTests: TuistTestCase {
    private let fileSystem = FileSystem()
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating!
    private var subject: BuiltAppBundleLocator!

    override func setUp() {
        super.setUp()
        xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocating()
        subject = BuiltAppBundleLocator(
            fileSystem: fileSystem,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator
        )
    }

    override func tearDown() {
        xcodeProjectBuildDirectoryLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_locateBuiltAppBundles_returns_existing_bundles_for_requested_platforms() async throws {
        let temporaryDirectory = try XCTUnwrap(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcworkspace")
        let simulatorBuildPath = temporaryDirectory.appending(component: "Debug-iphonesimulator")
        let deviceBuildPath = temporaryDirectory.appending(component: "Debug-iphoneos")

        try await fileSystem.makeDirectory(at: simulatorBuildPath)
        try await fileSystem.makeDirectory(at: deviceBuildPath)
        try await fileSystem.makeDirectory(at: simulatorBuildPath.appending(component: "App.app"))
        try await fileSystem.makeDirectory(at: deviceBuildPath.appending(component: "App.app"))

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.simulator(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(simulatorBuildPath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.device(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(deviceBuildPath)

        let bundles = try await subject.locateBuiltAppBundles(
            app: "App",
            projectPath: projectPath,
            derivedDataPath: nil,
            configuration: "Debug",
            platforms: [.iOS]
        )

        XCTAssertEqual(
            bundles,
            [
                BuiltAppBundle(
                    destinationType: .simulator(.iOS),
                    path: simulatorBuildPath.appending(component: "App.app")
                ),
                BuiltAppBundle(
                    destinationType: .device(.iOS),
                    path: deviceBuildPath.appending(component: "App.app")
                ),
            ]
        )
    }

    func test_locateBuiltAppBundlePath_throws_when_no_built_bundle_exists() async throws {
        let projectPath = try AbsolutePath(validating: "/Project/App.xcworkspace")
        let simulatorBuildPath = try AbsolutePath(validating: "/Derived/Build/Products/Debug-iphonesimulator")
        let deviceBuildPath = try AbsolutePath(validating: "/Derived/Build/Products/Debug-iphoneos")

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.simulator(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(simulatorBuildPath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.device(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(deviceBuildPath)

        do {
            _ = try await subject.locateBuiltAppBundlePath(
                app: "App",
                projectPath: projectPath,
                derivedDataPath: nil,
                configuration: "Debug",
                platforms: [.iOS]
            )
            XCTFail("Expected locateBuiltAppBundlePath to throw")
        } catch let error as BuiltAppBundleLocatorError {
            XCTAssertEqual(error, .noAppsFound(app: "App", configuration: "Debug"))
        }
    }

    func test_locateBuiltAppBundlePath_returns_single_unique_bundle_path() async throws {
        let temporaryDirectory = try XCTUnwrap(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcworkspace")
        let simulatorBuildPath = temporaryDirectory.appending(component: "Debug-iphonesimulator")
        let deviceBuildPath = temporaryDirectory.appending(component: "Debug-iphoneos")
        let bundlePath = simulatorBuildPath.appending(component: "App.app")

        try await fileSystem.makeDirectory(at: simulatorBuildPath)
        try await fileSystem.makeDirectory(at: deviceBuildPath)
        try await fileSystem.makeDirectory(at: bundlePath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.simulator(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(simulatorBuildPath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.device(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(deviceBuildPath)

        let resolvedPath = try await subject.locateBuiltAppBundlePath(
            app: "App",
            projectPath: projectPath,
            derivedDataPath: nil,
            configuration: "Debug",
            platforms: [.iOS]
        )

        XCTAssertEqual(resolvedPath, bundlePath)
    }

    func test_locateBuiltAppBundlePath_throws_when_multiple_unique_bundles_exist() async throws {
        let temporaryDirectory = try XCTUnwrap(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcworkspace")
        let simulatorBuildPath = temporaryDirectory.appending(component: "Debug-iphonesimulator")
        let deviceBuildPath = temporaryDirectory.appending(component: "Debug-iphoneos")
        let simulatorBundlePath = simulatorBuildPath.appending(component: "App.app")
        let deviceBundlePath = deviceBuildPath.appending(component: "App.app")

        try await fileSystem.makeDirectory(at: simulatorBuildPath)
        try await fileSystem.makeDirectory(at: deviceBuildPath)
        try await fileSystem.makeDirectory(at: simulatorBundlePath)
        try await fileSystem.makeDirectory(at: deviceBundlePath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.simulator(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(simulatorBuildPath)

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.device(.iOS)),
                projectPath: .value(projectPath),
                derivedDataPath: .value(nil),
                configuration: .value("Debug")
            )
            .willReturn(deviceBuildPath)

        do {
            _ = try await subject.locateBuiltAppBundlePath(
                app: "App",
                projectPath: projectPath,
                derivedDataPath: nil,
                configuration: "Debug",
                platforms: [.iOS]
            )
            XCTFail("Expected locateBuiltAppBundlePath to throw")
        } catch let error as BuiltAppBundleLocatorError {
            XCTAssertEqual(
                error,
                .multipleBuiltBundlesFound(
                    app: "App",
                    paths: [deviceBundlePath.pathString, simulatorBundlePath.pathString]
                )
            )
        }
    }
}
