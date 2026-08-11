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

    public static let none = SDKDeploymentTargets(iOS: nil, macOS: nil, watchOS: nil, tvOS: nil, visionOS: nil)

    public init(
        iOS: String? = nil,
        macOS: String? = nil,
        watchOS: String? = nil,
        tvOS: String? = nil,
        visionOS: String? = nil
    ) {
        self.iOS = iOS
        self.macOS = macOS
        self.watchOS = watchOS
        self.tvOS = tvOS
        self.visionOS = visionOS
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
            let deploymentTargets = await SDKDeploymentTargets(
                iOS: Self.minimumDeploymentTarget(sdk: "iphoneos", commandRunner: commandRunner),
                macOS: Self.minimumDeploymentTarget(sdk: "macosx", commandRunner: commandRunner),
                watchOS: Self.minimumDeploymentTarget(sdk: "watchos", commandRunner: commandRunner),
                tvOS: Self.minimumDeploymentTarget(sdk: "appletvos", commandRunner: commandRunner),
                visionOS: Self.minimumDeploymentTarget(sdk: "xros", commandRunner: commandRunner)
            )
            Logger.current.debug("Minimum deployment targets supported by the selected SDKs: \(deploymentTargets)")
            return deploymentTargets
        }
    }

    public func minimumDeploymentTargets() async -> SDKDeploymentTargets {
        await cachedDeploymentTargets.value()
    }

    private static func minimumDeploymentTarget(sdk: String, commandRunner: CommandRunning) async -> String? {
        do {
            let path = try await commandRunner
                .capture(arguments: ["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-path"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("SDKSettings.plist"))
            guard let plist = try PropertyListSerialization.propertyList(from: settings, format: nil) as? [String: Any],
                  let supportedTargets = plist["SupportedTargets"] as? [String: Any],
                  let target = supportedTargets[sdk] as? [String: Any]
            else {
                return nil
            }
            switch target["MinimumDeploymentTarget"] {
            case let version as String: return version
            case let version as NSNumber: return version.stringValue
            default: return nil
            }
        } catch {
            Logger.current.debug("Couldn't read the minimum deployment target of the \(sdk) SDK: \(error)")
            return nil
        }
    }
}

/// Caches the first realized value, coalescing concurrent callers onto a single build.
private actor AsyncCaching<T: Sendable> {
    private var cachedValue: T?
    private var inFlightTask: Task<T, Never>?
    private let builder: @Sendable () async -> T

    init(_ builder: @Sendable @escaping () async -> T) {
        self.builder = builder
    }

    func value() async -> T {
        if let cachedValue {
            return cachedValue
        }
        if let inFlightTask {
            return await inFlightTask.value
        }
        let task = Task { await builder() }
        inFlightTask = task
        let realizedValue = await task.value
        cachedValue = realizedValue
        inFlightTask = nil
        return realizedValue
    }
}

#if DEBUG
    extension SDKDeploymentTargetsProvider {
        public static var mocked: MockSDKDeploymentTargetsProviding? { current as? MockSDKDeploymentTargetsProviding }
    }
#endif
