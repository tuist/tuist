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
    /// Represents a simulated location used when running the provided run action
    public enum SimulatedLocation {
        case london
        case johannesburg
        case moscow
        case mumbai
        case tokyo
        case sydney
        case hongKong
        case honolulu
        case sanFrancisco
        case mexicoCity
        case newYork
        case rioDeJaneiro
        case custom(gpxFile: Path)

        /// A unique identifier string for the selected simulated location.
        ///
        /// In case of Xcode's simulated locations, this is a string representing the location.
        /// In case of a custom GPX file, this is a path to that file.
        public var identifier: String {
            switch self {
            case .london:
                return "London, England"
            case .johannesburg:
                return "Johannesburg, South Africa"
            case .moscow:
                return "Moscow, Russia"
            case .mumbai:
                return "Mumbai, India"
            case .tokyo:
                return "Tokyo, Japan"
            case .sydney:
                return "Sydney, Australia"
            case .hongKong:
                return "Hong Kong, China"
            case .honolulu:
                return "Honolulu, HI, USA"
            case .sanFrancisco:
                return "San Francisco, CA, USA"
            case .mexicoCity:
                return "Mexico City, Mexico"
            case .newYork:
                return "New York, NY, USA"
            case .rioDeJaneiro:
                return "Rio De Janeiro, Brazil"
            case let .custom(path):
                return path.pathString
            }
        }
    }
}

extension RunActionOptions.SimulatedLocation: Equatable, Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "London, England":
            self = .london
        case "Johannesburg, South Africa":
            self = .johannesburg
        case "Moscow, Russia":
            self = .moscow
        case "Mumbai, India":
            self = .mumbai
        case "Tokyo, Japan":
            self = .tokyo
        case "Sydney, Australia":
            self = .sydney
        case "Hong Kong, China":
            self = .hongKong
        case "Honolulu, HI, USA":
            self = .honolulu
        case "San Francisco, CA, USA":
            self = .sanFrancisco
        case "Mexico City, Mexico":
            self = .mexicoCity
        case "New York, NY, USA":
            self = .newYork
        case "Rio De Janeiro, Brazil":
            self = .rioDeJaneiro
        case _ where value.contains("/"):
            self = .custom(gpxFile: Path(value))
        default:
            throw CodingError.unknownLocation
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }

    enum CodingError: Error {
        case unknownLocation
    }
}
