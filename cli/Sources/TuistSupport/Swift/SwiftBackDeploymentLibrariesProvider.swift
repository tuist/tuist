import Command
import Foundation
import Mockable
import TuistThreadSafe

@Mockable
public protocol SwiftBackDeploymentLibrariesProviding: Sendable {
    /// `LD_RUNPATH_SEARCH_PATHS` entries exposing the active toolchain's Swift back-deployment
    /// compatibility dylibs (`libswiftCompatibilitySpan` and friends). Entries use build settings
    /// (`$(TOOLCHAIN_DIR)`, `$(PLATFORM_NAME)`) so generated projects stay portable.
    func runpathSearchPaths() async throws -> [String]
}

/// The directory holding these dylibs is Swift-version specific (`usr/lib/swift-6.2`, and
/// `swift-6.3`, ... in future toolchains), so it is discovered from the active toolchain rather
/// than hardcoded to any Swift version.
public final class SwiftBackDeploymentLibrariesProvider: SwiftBackDeploymentLibrariesProviding, @unchecked Sendable {
    @TaskLocal public static var current: SwiftBackDeploymentLibrariesProviding = SwiftBackDeploymentLibrariesProvider()

    private static let compatibilitySpanDylib = "libswiftCompatibilitySpan.dylib"

    private let commandRunner: CommandRunning
    private let cachedRunpathSearchPaths: TuistThreadSafe.ThreadSafe<[String]?> = .init(nil)

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func runpathSearchPaths() async throws -> [String] {
        if let cachedRunpathSearchPaths = cachedRunpathSearchPaths.value {
            return cachedRunpathSearchPaths
        }
        let value = await resolveRunpathSearchPaths()
        cachedRunpathSearchPaths.mutate { $0 = value }
        return value
    }

    private func resolveRunpathSearchPaths() async -> [String] {
        guard let libraryDirectory = try? await toolchainLibraryDirectory() else {
            return []
        }
        return Self.compatibilitySpanSegments(in: libraryDirectory)
            .sorted()
            .map { "$(TOOLCHAIN_DIR)/usr/lib/\($0)/$(PLATFORM_NAME)" }
    }

    private func toolchainLibraryDirectory() async throws -> String {
        let swiftcPath = try await commandRunner
            .capture(arguments: ["/usr/bin/xcrun", "--find", "swiftc"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // <toolchain>/usr/bin/swiftc -> <toolchain>/usr/lib
        let usrBinDirectory = (swiftcPath as NSString).deletingLastPathComponent
        let usrDirectory = (usrBinDirectory as NSString).deletingLastPathComponent
        return (usrDirectory as NSString).appendingPathComponent("lib")
    }

    private static func compatibilitySpanSegments(in libraryDirectory: String) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: libraryDirectory)) ?? []
        return entries.filter { entry in
            entry.hasPrefix("swift-") &&
                segmentShipsCompatibilitySpan((libraryDirectory as NSString).appendingPathComponent(entry))
        }
    }

    private static func segmentShipsCompatibilitySpan(_ segmentDirectory: String) -> Bool {
        let platforms = (try? FileManager.default.contentsOfDirectory(atPath: segmentDirectory)) ?? []
        return platforms.contains { platform in
            let dylib = ((segmentDirectory as NSString).appendingPathComponent(platform) as NSString)
                .appendingPathComponent(compatibilitySpanDylib)
            return FileManager.default.fileExists(atPath: dylib)
        }
    }
}

#if DEBUG
    extension SwiftBackDeploymentLibrariesProvider {
        public static var mocked: MockSwiftBackDeploymentLibrariesProviding? {
            current as? MockSwiftBackDeploymentLibrariesProviding
        }
    }
#endif
