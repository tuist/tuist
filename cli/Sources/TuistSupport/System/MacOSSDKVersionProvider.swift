import Foundation
import Mockable

@Mockable
public protocol MacOSSDKVersionProviding: Sendable {
    /// Returns the version of the macOS SDK from the currently selected Xcode toolchain.
    ///
    /// This is the SDK that Swift uses to build modules and is reported in errors like
    /// "cannot load module 'X' built with SDK 'macosx26.4' when using SDK 'macosx26.5'".
    ///
    /// - Returns: macOS SDK version (for example, "26.5").
    /// - Throws: An error if the SDK version can't be determined.
    func macOSSDKVersion() throws -> String
}

public struct MacOSSDKVersionProvider: MacOSSDKVersionProviding {
    @TaskLocal public static var current: MacOSSDKVersionProviding = MacOSSDKVersionProvider(System())

    let cachedMacOSSDKVersion: ThrowableCaching<String>

    init(_ system: Systeming) {
        cachedMacOSSDKVersion = ThrowableCaching<String> {
            try system.capture(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]).spm_chomp()
        }
    }

    public func macOSSDKVersion() throws -> String {
        try cachedMacOSSDKVersion.value
    }
}
