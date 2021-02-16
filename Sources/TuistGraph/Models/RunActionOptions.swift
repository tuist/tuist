import Foundation
import TSCBasic

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700)
    public let storeKitConfigurationPath: AbsolutePath?

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - storeKitConfigurationPath: The absolute path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     The default value is `nil`, which results in no
    ///     configuration defined for the scheme
    public init(
        storeKitConfigurationPath: AbsolutePath? = nil
    ) {
        self.storeKitConfigurationPath = storeKitConfigurationPath
    }
}
