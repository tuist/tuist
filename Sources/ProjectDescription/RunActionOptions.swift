/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable, Sendable {
    /// Language to use when running the app.
    public var language: SchemeLanguage?

    /// Region to use when running the app.
    public var region: String?

    /// The path of the
    /// [StoreKit configuration
    /// file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    public var storeKitConfigurationPath: Path?

    /// A simulated GPS location to use when running the app.
    public var simulatedLocation: ProjectDescription.SimulatedLocation?

    /// Configure your project to work with the Metal frame debugger.
    public var enableGPUFrameCaptureMode: GPUFrameCaptureMode

    /// Creates an `RunActionOptions` instance
    ///
    /// - Parameters:
    ///     - language: language (e.g. "pl").
    ///
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration
    /// file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
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
        simulatedLocation: ProjectDescription.SimulatedLocation? = nil,
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
    ///     - language: language (e.g. "en").
    ///
    ///     - region: region (e.g. "US").
    ///
    ///     - storeKitConfigurationPath: The path of the
    ///     [StoreKit configuration
    /// file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     Please note that this file is automatically added to the Project/Workspace. You should not add it manually.
    ///     The default value is `nil`, which results in no configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///     Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.
    ///
    ///     - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    ///     If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    ///     You can disable it to test your app in best performance.
    public static func options(
        language: SchemeLanguage? = nil,
        region: String? = nil,
        storeKitConfigurationPath: Path? = nil,
        simulatedLocation: ProjectDescription.SimulatedLocation? = nil,
        enableGPUFrameCaptureMode: GPUFrameCaptureMode = GPUFrameCaptureMode.default
    ) -> Self {
        self.init(
            language: language,
            region: region,
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation,
            enableGPUFrameCaptureMode: enableGPUFrameCaptureMode
        )
    }
}

extension RunActionOptions {
    public enum GPUFrameCaptureMode: String, Codable, Equatable, Sendable {
        case autoEnabled
        case metal
        case openGL
        case disabled

        public static var `default`: GPUFrameCaptureMode {
            .autoEnabled
        }
    }
}

extension RunActionOptions {
    @available(*, deprecated, message: "Use ProjectDescription.SimulatedLocation directly instead.")
    public typealias SimulatedLocation = ProjectDescription.SimulatedLocation
}
