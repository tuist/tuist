import Command
import Foundation
import Mockable

@Mockable
public protocol SwiftBackDeploymentLibrariesProviding {
    /// `LD_RUNPATH_SEARCH_PATHS` entries exposing the active toolchain's Swift back-deployment
    /// compatibility dylibs (`libswiftCompatibilitySpan` and friends). Entries are expressed with
    /// build settings (`$(TOOLCHAIN_DIR)`, `$(PLATFORM_NAME)`) so generated projects stay portable.
    func runpathSearchPaths() async throws -> [String]
}

/// These compatibility dylibs live in a Swift-version-specific toolchain directory
/// (`usr/lib/swift-6.2`, and `swift-6.3`, ... in future toolchains), so the segment is discovered
/// from the active toolchain rather than hardcoded to any Swift version.
public struct SwiftBackDeploymentLibrariesProvider: SwiftBackDeploymentLibrariesProviding {
    @TaskLocal public static var current: SwiftBackDeploymentLibrariesProviding =
        SwiftBackDeploymentLibrariesProvider(commandRunner: CommandRunner())

    private static let compatibilitySpanDylib = "libswiftCompatibilitySpan.dylib"

    private let cachedRunpathSearchPaths: AsyncThrowableCaching<[String]>

    init(commandRunner: CommandRunning) {
        cachedRunpathSearchPaths = AsyncThrowableCaching<[String]> {
            guard let libraryDirectory = try? await SwiftBackDeploymentLibrariesProvider
                .toolchainLibraryDirectory(commandRunner: commandRunner)
            else {
                return []
            }
            return SwiftBackDeploymentLibrariesProvider.compatibilitySpanSegments(in: libraryDirectory)
                .sorted()
                .map { "$(TOOLCHAIN_DIR)/usr/lib/\($0)/$(PLATFORM_NAME)" }
        }
    }

    public func runpathSearchPaths() async throws -> [String] {
        try await cachedRunpathSearchPaths.value()
    }

    private static func toolchainLibraryDirectory(commandRunner: CommandRunning) async throws -> String {
        let swiftcPath = try await commandRunner.capture(arguments: ["/usr/bin/xcrun", "--find", "swiftc"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // <toolchain>/usr/bin/swiftc -> <toolchain>/usr/lib
        let usrBinDirectory = (swiftcPath as NSString).deletingLastPathComponent
        let usrDirectory = (usrBinDirectory as NSString).deletingLastPathComponent
        return (usrDirectory as NSString).appendingPathComponent("lib")
    }

    /// `swift-*` directories that actually ship the compatibility-span dylib for at least one platform.
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

private actor AsyncThrowableCaching<T: Sendable> {
    private var cachedValue: T?
    private var inFlightTask: Task<T, Error>?
    private let builder: @Sendable () async throws -> T

    init(_ builder: @Sendable @escaping () async throws -> T) {
        self.builder = builder
    }

    func value() async throws -> T {
        if let cachedValue {
            return cachedValue
        }
        if let inFlightTask {
            return try await inFlightTask.value
        }
        let task = Task { try await builder() }
        inFlightTask = task
        do {
            let realizedValue = try await task.value
            cachedValue = realizedValue
            inFlightTask = nil
            return realizedValue
        } catch {
            inFlightTask = nil
            throw error
        }
    }
}
