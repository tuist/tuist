import Foundation

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    public let storeKitConfigurationPath: Path?

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    init(
        storeKitConfigurationPath: Path? = nil
    ) {
        self.storeKitConfigurationPath = storeKitConfigurationPath
    }

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    public static func options(
        storeKitConfigurationPath: Path? = nil
    ) -> Self {
        self.init(storeKitConfigurationPath: storeKitConfigurationPath)
    }
}
