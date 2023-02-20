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
        scheme: Scheme,
        version: Version?,
        deviceName: String?,
        graphTraverser: GraphTraversing,
        simulatorController: SimulatorControlling
    ) async throws -> XcodeBuildDestination {
        switch target.deploymentTargets.first!.platform {
        case .iOS, .tvOS, .watchOS:
            let minVersion: Version?
            if let deploymentTarget = target.deploymentTargets.first(where: { $0.platform == target.deploymentTargets.first!.platform } ) {
                minVersion = deploymentTarget.version.version()
            } else {
                minVersion = scheme.targetDependencies()
                    .compactMap {
                        graphTraverser
                            .directLocalTargetDependencies(path: $0.projectPath, name: $0.name)
                            .map(\.target)
                            .flatMap(\.deploymentTargets)
                            .first(where: { $0.platform == target.deploymentTargets.first!.platform } )
                            .flatMap { $0.version.version() }
                    }
                    .sorted()
                    .first
                
            }

            let deviceAndRuntime = try await simulatorController.findAvailableDevice(
                platform: target.deploymentTargets.first!.platform,
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
