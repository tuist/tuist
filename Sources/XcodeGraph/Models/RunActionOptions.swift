import Foundation
import TSCBasic

/// Options for the `RunAction` action
public struct RunActionOptions: Equatable, Codable {
    /// App Language.
    public let language: String?

    /// App Region.
    public let region: String?

    /// The path of the
    /// [StoreKit configuration
    /// file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700)
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
    ///     [StoreKit configuration
    /// file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    ///     The default value is `nil`, which results in no
    ///     configuration defined for the scheme
    ///
    ///     - simulatedLocation: The simulated GPS location to use when running the app.
    ///
    ///     - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    ///     If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    ///     You can disable it to test your app in best performance.

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
