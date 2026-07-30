import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistTesting

@testable import TuistSupport

struct SwiftBackDeploymentLibrariesProviderTests {
    @Test func runpathSearchPaths_alwaysEmitsSwift62Fallback_whenToolchainDiscoveryFails() async throws {
        // The canonical `swift-6.2` segment must be emitted even when the toolchain can't be
        // discovered (e.g. `xcrun` unavailable), mirroring how `swift-build` hardcodes the segment.
        let commandRunner = MockCommandRunner()
        commandRunner.errorCommand(["/usr/bin/xcrun", "--find", "swiftc"])

        let subject = SwiftBackDeploymentLibrariesProvider(commandRunner: commandRunner)

        let paths = try await subject.runpathSearchPaths()

        #expect(paths == ["$(TOOLCHAIN_DIR)/usr/lib/swift-6.2/$(PLATFORM_NAME)"])
    }

    @Test(.inTemporaryDirectory) func runpathSearchPaths_dedupesDiscoveredSegmentWithFallback() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Lay out a fake toolchain whose `swift-6.2` directory ships the compatibility dylib, so
        // discovery finds the same segment the fallback seeds.
        let libraryDirectory = temporaryDirectory.appending(components: "usr", "lib")
        let segmentDirectory = libraryDirectory.appending(components: "swift-6.2", "macosx")
        try FileManager.default.createDirectory(atPath: segmentDirectory.pathString, withIntermediateDirectories: true)
        try FileManager.default.createFile(
            atPath: segmentDirectory.appending(component: "libswiftCompatibilitySpan.dylib").pathString,
            contents: Data()
        )

        let commandRunner = MockCommandRunner()
        commandRunner.succeedCommand(
            ["/usr/bin/xcrun", "--find", "swiftc"],
            output: temporaryDirectory.appending(components: "usr", "bin", "swiftc").pathString
        )

        let subject = SwiftBackDeploymentLibrariesProvider(commandRunner: commandRunner)

        let paths = try await subject.runpathSearchPaths()

        #expect(paths == ["$(TOOLCHAIN_DIR)/usr/lib/swift-6.2/$(PLATFORM_NAME)"])
    }

    @Test(.inTemporaryDirectory) func runpathSearchPaths_discoversSegmentsBeyondTheFallback() async throws {
        // The hardcoded `swift-6.2` fallback is always present, while discovery still surfaces any
        // additional `swift-*` segment a future toolchain may ship.
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let libraryDirectory = temporaryDirectory.appending(components: "usr", "lib")
        for segment in ["swift-6.2", "swift-9.9"] {
            let segmentDirectory = libraryDirectory.appending(components: segment, "macosx")
            try FileManager.default.createDirectory(
                atPath: segmentDirectory.pathString,
                withIntermediateDirectories: true
            )
            try FileManager.default.createFile(
                atPath: segmentDirectory.appending(component: "libswiftCompatibilitySpan.dylib").pathString,
                contents: Data()
            )
        }

        let commandRunner = MockCommandRunner()
        commandRunner.succeedCommand(
            ["/usr/bin/xcrun", "--find", "swiftc"],
            output: temporaryDirectory.appending(components: "usr", "bin", "swiftc").pathString
        )

        let subject = SwiftBackDeploymentLibrariesProvider(commandRunner: commandRunner)

        let paths = try await subject.runpathSearchPaths()

        #expect(paths == [
            "$(TOOLCHAIN_DIR)/usr/lib/swift-6.2/$(PLATFORM_NAME)",
            "$(TOOLCHAIN_DIR)/usr/lib/swift-9.9/$(PLATFORM_NAME)",
        ])
    }
}
