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

/// Swift ships back-deployment compatibility dylibs in a versioned prebuilt directory inside the
/// toolchain (`usr/lib/swift-6.2/$(PLATFORM_NAME)`), separate from the runtime in the SDK/OS.
/// SPM products that adopt back-deployed stdlib types (Span, RawSpan, ...) reference them via
/// `@rpath`, so the directory has to be exposed to dyld through `LD_RUNPATH_SEARCH_PATHS` or
/// loading the product fails with `Library not loaded: @rpath/libswiftCompatibilitySpan.dylib`.
///
/// `swift-6.2` is a Swift ABI version marker rather than the compiler version: it stays constant
/// across compiler releases (Swift 6.2, 6.3.x, ... all ship `swift-6.2`), which is why the Xcode
/// build system hardcodes it in `swift-build` (`LinkerTools.computeRPaths` and
/// `EmbedSwiftStdLibTaskAction`). We mirror that here by always emitting `swift-6.2`, and only
/// additionally discover other `swift-*` segments the active toolchain may ship. The toolchain
/// path is emitted directly (instead of setting `ADD_TOOLCHAIN_SPAN_BACK_DEPLOY_RPATH`) so the run
/// path is present regardless of the Xcode build-system version, which matters for prebuilt SPM
/// artifacts that already carry the `@rpath/libswiftCompatibilitySpan.dylib` load command.
public final class SwiftBackDeploymentLibrariesProvider: SwiftBackDeploymentLibrariesProviding, @unchecked Sendable {
    @TaskLocal public static var current: SwiftBackDeploymentLibrariesProviding = SwiftBackDeploymentLibrariesProvider()

    private static let compatibilitySpanDylib = "libswiftCompatibilitySpan.dylib"
    /// The versioned segment Apple's toolchains ship the Span back-deployment dylibs under. It is a
    /// Swift ABI marker that stays constant across compiler releases (6.3.x still uses `swift-6.2`),
    /// so it is hardcoded rather than derived from the active toolchain's compiler version.
    private static let spanBackDeploymentSegment = "swift-6.2"

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
        // Always include the canonical Span back-deployment segment so a failed or empty toolchain
        // scan (e.g. `xcrun` unavailable, unexpected layout) doesn't silently drop the run path.
        // This matches `swift-build`, which hardcodes `swift-6.2` instead of scanning.
        var segments: Set<String> = [Self.spanBackDeploymentSegment]
        if let libraryDirectory = try? await toolchainLibraryDirectory() {
            segments.formUnion(Self.discoveredCompatibilitySpanSegments(in: libraryDirectory))
        }
        return segments.sorted()
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

    private static func discoveredCompatibilitySpanSegments(in libraryDirectory: String) -> Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: libraryDirectory)) ?? []
        return Set(entries.filter { entry in
            entry.hasPrefix("swift-") &&
                segmentShipsCompatibilitySpan((libraryDirectory as NSString).appendingPathComponent(entry))
        })
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
