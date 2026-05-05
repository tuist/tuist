import Command
import Foundation
import Mockable
import TuistThreadSafe

@Mockable
public protocol MacOSSDKVersionProviding: Sendable {
    /// Returns the version of the macOS SDK from the currently selected Xcode toolchain.
    ///
    /// This is the SDK that Swift uses to build modules and is reported in errors like
    /// "cannot load module 'X' built with SDK 'macosx26.4' when using SDK 'macosx26.5'".
    ///
    /// - Returns: macOS SDK version (for example, "26.5").
    /// - Throws: An error if the SDK version can't be determined.
    func macOSSDKVersion() async throws -> String
}

public final class MacOSSDKVersionProvider: MacOSSDKVersionProviding, @unchecked Sendable {
    @TaskLocal public static var current: MacOSSDKVersionProviding = MacOSSDKVersionProvider()

    private let commandRunner: CommandRunning
    private let cachedVersion: TuistThreadSafe.ThreadSafe<String?> = .init(nil)

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func macOSSDKVersion() async throws -> String {
        if let cachedVersion = cachedVersion.value {
            return cachedVersion
        }
        let value = try await commandRunner
            .run(arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cachedVersion.mutate { $0 = value }
        return value
    }
}

#if DEBUG
    extension MacOSSDKVersionProvider {
        public static var mocked: MockMacOSSDKVersionProviding? { current as? MockMacOSSDKVersionProviding }
    }
#endif
