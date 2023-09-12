import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

extension XcodeBuildDestination {
    /// Finds the `XcodeBuildDestination` that matches the arguments provided
    /// - Parameters:
    ///   - target: The target where the scheme is defined.
    ///   - scheme: The scheme to use.
    ///   - version: The OS version of the device to use.
    ///   - deviceName: The name of the device to use.
    ///   - graphTraverser: The Graph traverser.
    ///   - simulatorController: The simulator controller.
    /// - Returns: The `XcodeBuildDestination` that is compatible with the given arguments.
    public static func find(
        for target: Target,
        on platform: TuistGraph.Platform,
        scheme: Scheme,
        version: Version?,
        deviceName: String?,
        graphTraverser: GraphTraversing,
        simulatorController: SimulatorControlling
    ) async throws -> XcodeBuildDestination {
        switch platform {
        case .iOS, .tvOS, .watchOS, .visionOS:
            let minVersion: Version?
            if let deploymentTargetVersion = target.deploymentTargets[platform] {
                minVersion = deploymentTargetVersion.version()
            } else {
                minVersion = scheme.targetDependencies()
                    .flatMap {
                        graphTraverser
                            .directLocalTargetDependencies(path: $0.projectPath, name: $0.name)
                            .compactMap { $0.target.deploymentTargets[platform]?.version() }
                    }
                    .sorted()
                    .first
            }

            let deviceAndRuntime = try await simulatorController.findAvailableDevice(
                platform: platform,
                version: version,
                minVersion: minVersion,
                deviceName: deviceName
            )
            return .device(deviceAndRuntime.device.udid)
        case .macOS:
            return .mac
        }
    }
}
