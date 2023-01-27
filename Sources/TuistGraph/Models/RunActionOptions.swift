import Foundation
import TSCBasic

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// App Language.
    public let language: String?

    /// App Region.
    public let region: String?

    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700)
    public let storeKitConfigurationPath: AbsolutePath?

    /// A simulated location used when running the provided run action.
    public let simulatedLocation: SimulatedLocation?

    /// Configure your project to work with the Metal frame debugger.
    public let enableGPUFrameCaptureMode: GPUFrameCaptureMode

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
    ///
    ///     - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    ///     If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    ///     You can disable it to test your app in best perfomance.

    public init(
        language: String? = nil,
        region: String? = nil,
        storeKitConfigurationPath: AbsolutePath? = nil,
        simulatedLocation: SimulatedLocation? = nil,
        enableGPUFrameCaptureMode: GPUFrameCaptureMode = .autoEnabled
    ) {
        self.language = language
        self.region = region
        self.storeKitConfigurationPath = storeKitConfigurationPath
        self.simulatedLocation = simulatedLocation
        self.enableGPUFrameCaptureMode = enableGPUFrameCaptureMode
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

extension RunActionOptions {
    public enum GPUFrameCaptureMode: String, Codable, Equatable {
        case autoEnabled
        case metal
        case openGL
        case disabled

        public static var `default`: GPUFrameCaptureMode {
            .autoEnabled
        }
    }
}
