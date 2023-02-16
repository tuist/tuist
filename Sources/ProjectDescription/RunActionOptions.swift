import Foundation

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// Language to use when running the app.
    public let language: SchemeLanguage?

    /// Region to use when running the app.
    public let region: String?

    /// The path of the
    /// [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    public let storeKitConfigurationPath: Path?

    /// A simulated GPS location to use when running the app.
    public let simulatedLocation: SimulatedLocation?

    /// Configure your project to work with the Metal frame debugger.
    public let enableGPUFrameCaptureMode: GPUFrameCaptureMode

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - language: language (e.g. "pl").
    ///
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///     Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.
    ///
    ///     - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    ///     If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    ///     You can disable it to test your app in best perfomance.
    init(
        language: SchemeLanguage? = nil,
        region: String? = nil,
        storeKitConfigurationPath: Path? = nil,
        simulatedLocation: SimulatedLocation? = nil,
        enableGPUFrameCaptureMode: GPUFrameCaptureMode = GPUFrameCaptureMode.default
    ) {
        self.language = language
        self.region = region
        self.storeKitConfigurationPath = storeKitConfigurationPath
        self.simulatedLocation = simulatedLocation
        self.enableGPUFrameCaptureMode = enableGPUFrameCaptureMode
    }

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - language: language (e.g. "pl").
    ///
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///     Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.
    ///
    ///     - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    ///     If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    ///     You can disable it to test your app in best perfomance.

    public static func options(
        language: SchemeLanguage? = nil,
        storeKitConfigurationPath: Path? = nil,
        simulatedLocation: SimulatedLocation? = nil,
        enableGPUFrameCaptureMode: GPUFrameCaptureMode = GPUFrameCaptureMode.default
    ) -> Self {
        self.init(
            language: language,
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation,
            enableGPUFrameCaptureMode: enableGPUFrameCaptureMode
        )
    }
}

extension RunActionOptions {
    /// Simulated location represents a GPS location that is used when running an app on the simulator.
    public struct SimulatedLocation: Codable, Equatable {
        /// The identifier of the location (e.g. London, England)
        public let identifier: String?
        /// Path to a .gpx file that indicates the location
        public let gpxFile: Path?

        private init(
            identifier: String? = nil,
            gpxFile: Path? = nil
        ) {
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
