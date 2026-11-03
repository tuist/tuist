import TuistCore
import TuistLogging
import XcodeGraph

enum CacheDestinationGraphMapperError: FatalError, Equatable {
    case missingDestination(target: String, simulator: Bool)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case let .missingDestination(target, simulator):
            return "Target '\(target)' has no \(simulator ? "simulator" : "device") or native macOS destination. Regenerate with --destination all."
        }
    }
}

/// Restricts an explicitly selected workspace after source hashing and binary replacement.
/// Native macOS targets, including macros and their dependencies, retain their normal SDKs.
public struct CacheDestinationGraphMapper: GraphMapping {
    private let simulator: Bool

    public init(simulator: Bool) {
        self.simulator = simulator
    }

    // swiftlint:disable large_tuple
    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph
        graph.projects = try graph.projects.mapValues { project in
            var project = project
            project.targets = try project.targets.mapValues { target in
                guard target.supportedPlatforms.contains(where: \.hasSimulators),
                      target.product != .macro, !target.isAggregate else { return target }

                var target = target
                target.destinations.remove(.macCatalyst)
                target.destinations.remove(.macWithiPadDesign)
                target.destinations.remove(.appleVisionWithiPadDesign)
                guard !target.destinations.isEmpty else {
                    throw CacheDestinationGraphMapperError.missingDestination(target: target.name, simulator: simulator)
                }
                let sdks = target.supportedPlatforms.filter(\.hasSimulators).compactMap {
                    simulator ? $0.xcodeSimulatorSDK : $0.xcodeDeviceSDK
                }.sorted()
                let settings = target.settings ?? .default
                let restrictions: SettingsDictionary = [
                    "SUPPORTED_PLATFORMS": .string((sdks + (target.supports(.macOS) ? ["macosx"] : []))
                        .joined(separator: " ")),
                    "SDKROOT": .string(target.supports(.macOS) || sdks.count > 1 ? "auto" : sdks[0]),
                    "SUPPORTS_MACCATALYST": "NO",
                    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
                ]
                func restrict(_ settings: SettingsDictionary) -> SettingsDictionary {
                    let settings = settings.filter { key, _ in
                        !restrictions.keys.contains(String(key.prefix(while: { $0 != "[" })))
                    }
                    return settings.merging(restrictions) { _, restriction in restriction }
                }
                let configurations = settings.configurations.mapValues { configuration -> Configuration? in
                    guard var configuration else { return nil }
                    configuration.settings = restrict(configuration.settings)
                    return configuration
                }
                target.settings = Settings(
                    base: restrict(settings.base),
                    baseDebug: restrict(settings.baseDebug),
                    configurations: configurations,
                    defaultSettings: settings.defaultSettings,
                    defaultConfiguration: settings.defaultConfiguration
                )
                return target
            }
            return project
        }
        return (graph, [], environment)
    }
    // swiftlint:enable large_tuple
}
