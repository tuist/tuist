import Foundation

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    public let storeKitConfigurationPath: Path?

    /// A simulated location used when running the provided run action.
    public let simulatedLocation: SimulatedLocation?

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///     Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.
    init(
        storeKitConfigurationPath: Path? = nil,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.storeKitConfigurationPath = storeKitConfigurationPath
        self.simulatedLocation = simulatedLocation
    }

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///     Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.
    public static func options(
        storeKitConfigurationPath: Path? = nil,
        simulatedLocation: SimulatedLocation? = nil
    ) -> Self {
        self.init(
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation
        )
    }
}

extension RunActionOptions {
    /// Represents a simulated location used when running the provided run action.
    public struct SimulatedLocation: Codable, Equatable {
        public let identifier: String?
        public let gpxFile: Path?

        private init(identifier: String? = nil,
                     gpxFile: Path? = nil)
        {
            self.identifier = identifier
            self.gpxFile = gpxFile
        }

        public static func custom(gpxFile: Path) -> SimulatedLocation {
            .init(gpxFile: gpxFile)
        }

        public static var london: SimulatedLocation {
            .init(identifier: "London, England")
        }

        public static var johannesburg: SimulatedLocation {
            .init(identifier: "Johannesburg, South Africa")
        }

        public static var moscow: SimulatedLocation {
            .init(identifier: "Moscow, Russia")
        }

        public static var mumbai: SimulatedLocation {
            .init(identifier: "Mumbai, India")
        }

        public static var tokyo: SimulatedLocation {
            .init(identifier: "Tokyo, Japan")
        }

        public static var sydney: SimulatedLocation {
            .init(identifier: "Sydney, Australia")
        }

        public static var hongKong: SimulatedLocation {
            .init(identifier: "Hong Kong, China")
        }

        public static var honolulu: SimulatedLocation {
            .init(identifier: "Honolulu, HI, USA")
        }

        public static var sanFrancisco: SimulatedLocation {
            .init(identifier: "San Francisco, CA, USA")
        }

        public static var mexicoCity: SimulatedLocation {
            .init(identifier: "Mexico City, Mexico")
        }

        public static var newYork: SimulatedLocation {
            .init(identifier: "New York, NY, USA")
        }

        public static var rioDeJaneiro: SimulatedLocation {
            .init(identifier: "Rio De Janeiro, Brazil")
        }
    }
}
