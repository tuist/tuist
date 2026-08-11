import struct Command.CommandRunner
import protocol Command.CommandRunning
import Foundation
import Mockable
import TuistLogging

/// The oldest deployment target that each platform SDK supports.
public struct SDKDeploymentTargets: Equatable, Sendable {
    public let iOS: String?
    public let macOS: String?
    public let watchOS: String?
    public let tvOS: String?
    public let visionOS: String?
    /// Mac Catalyst builds use the iOS deployment target, but the Catalyst variant of the macOS SDK
    /// supports a newer floor than the iOS SDK does.
    public let macCatalyst: String?

    public static let none = SDKDeploymentTargets()

    public init(
        iOS: String? = nil,
        macOS: String? = nil,
        watchOS: String? = nil,
        tvOS: String? = nil,
        visionOS: String? = nil,
        macCatalyst: String? = nil
    ) {
        self.iOS = iOS
        self.macOS = macOS
        self.watchOS = watchOS
        self.tvOS = tvOS
        self.visionOS = visionOS
        self.macCatalyst = macCatalyst
    }
}

@Mockable
public protocol SDKDeploymentTargetsProviding: Sendable {
    /// Returns the oldest deployment target that each SDK of the selected Xcode can build for.
    ///
    /// Building for a version below it fails with "the range of supported deployment target versions is X to Y".
    /// A platform whose SDK is not installed, and every platform when no Xcode is available, is `nil`.
    func minimumDeploymentTargets() async -> SDKDeploymentTargets
}

public struct SDKDeploymentTargetsProvider: SDKDeploymentTargetsProviding {
    @TaskLocal public static var current: SDKDeploymentTargetsProviding = SDKDeploymentTargetsProvider()

    private let cachedDeploymentTargets: AsyncCaching<SDKDeploymentTargets>

    public init(commandRunner: CommandRunning = CommandRunner()) {
        cachedDeploymentTargets = AsyncCaching {
            let macOSTargets = await Self.supportedTargets(sdk: "macosx", commandRunner: commandRunner)
            let deploymentTargets = await SDKDeploymentTargets(
                iOS: Self.minimumDeploymentTarget(sdk: "iphoneos", commandRunner: commandRunner),
                macOS: Self.minimumDeploymentTarget(of: "macosx", in: macOSTargets),
                watchOS: Self.minimumDeploymentTarget(sdk: "watchos", commandRunner: commandRunner),
                tvOS: Self.minimumDeploymentTarget(sdk: "appletvos", commandRunner: commandRunner),
                visionOS: Self.minimumDeploymentTarget(sdk: "xros", commandRunner: commandRunner),
                macCatalyst: Self.minimumDeploymentTarget(of: "iosmac", in: macOSTargets)
            )
            Logger.current.debug("Minimum deployment targets supported by the selected SDKs: \(deploymentTargets)")
            return deploymentTargets
        }
    }

    public func minimumDeploymentTargets() async -> SDKDeploymentTargets {
        await cachedDeploymentTargets.value()
    }

    private static func minimumDeploymentTarget(sdk: String, commandRunner: CommandRunning) async -> String? {
        await minimumDeploymentTarget(of: sdk, in: supportedTargets(sdk: sdk, commandRunner: commandRunner))
    }

    /// Returns the `SupportedTargets` of an SDK, keyed by target name. A single SDK describes more than one
    /// target: the macOS SDK covers both `macosx` and the Mac Catalyst `iosmac`.
    private static func supportedTargets(sdk: String, commandRunner: CommandRunning) async -> [String: Any] {
        do {
            let path = try await commandRunner
                .capture(arguments: ["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-path"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("SDKSettings.plist"))
            guard let plist = try PropertyListSerialization.propertyList(from: settings, format: nil) as? [String: Any],
                  let supportedTargets = plist["SupportedTargets"] as? [String: Any]
            else {
                return [:]
            }
            return supportedTargets
        } catch {
            Logger.current.debug("Couldn't read the supported targets of the \(sdk) SDK: \(error)")
            return [:]
        }
    }

    private static func minimumDeploymentTarget(of target: String, in supportedTargets: [String: Any]) -> String? {
        guard let target = supportedTargets[target] as? [String: Any] else { return nil }
        return target["MinimumDeploymentTarget"] as? String
    }
}

#if DEBUG
    extension SDKDeploymentTargetsProvider {
        public static var mocked: MockSDKDeploymentTargetsProviding? { current as? MockSDKDeploymentTargetsProviding }
    }
#endif
