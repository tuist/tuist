import Foundation
import TSCBasic

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// App Language.
    public let language: String?

    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700)
    public let storeKitConfigurationPath: AbsolutePath?

    /// A simulated location used when running the provided run action.
    public let simulatedLocation: SimulatedLocation?

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - language: language (e.g. "pl").
    ///
    ///     - storeKitConfigurationPath: The absolute path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     The default value is `nil`, which results in no
    ///     configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    public init(
        language: String? = nil,
        storeKitConfigurationPath: AbsolutePath? = nil,
        simulatedLocation: SimulatedLocation? = nil
    ) {
        self.language = language
        self.storeKitConfigurationPath = storeKitConfigurationPath
        self.simulatedLocation = simulatedLocation
    }
}

extension RunActionOptions {
    public enum SimulatedLocation {
        case gpxFile(AbsolutePath)
        case reference(String)

        /// A unique identifier string for the selected simulated location.
        ///
        /// In case of Xcode's simulated locations, this is a string representing the location.
        /// In case of a custom GPX file, this is a path to that file.
        public var identifier: String {
            switch self {
            case let .gpxFile(path):
                return path.pathString
            case let .reference(identifier):
                return identifier
            }
        }

        /// A reference type is 1 if using Xcode's built-in simulated locations.
        /// Otherwise, it is 0.
        public var referenceType: String {
            if case .gpxFile = self { return "0" }
            return "1"
        }
    }
}

extension RunActionOptions.SimulatedLocation: Equatable, Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        guard value.hasSuffix(".gpx") else {
            self = .reference(value)
            return
        }

        self = .gpxFile(try AbsolutePath(validating: value))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}
