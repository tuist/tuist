import TuistCore
import TuistLogging
import XcodeGraph

enum SimulatorOnlyGraphMapperError: FatalError, Equatable {
    case missingSimulatorDestination(target: String)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case let .missingSimulatorDestination(target):
            return "Target '\(target)' has no simulator or native macOS destination. Regenerate without --simulator-only."
        }
    }
}

/// Restricts an explicitly simulator-only workspace after source hashing and binary replacement.
/// Native macOS targets, including macros and their dependencies, retain their normal SDKs.
public struct SimulatorOnlyGraphMapper: GraphMapping {
    public init() {}

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
                    throw SimulatorOnlyGraphMapperError.missingSimulatorDestination(target: target.name)
                }
                let simulatorSDKs = target.supportedPlatforms.compactMap(\.xcodeSimulatorSDK).sorted()
                let settings = target.settings ?? .default
                let restrictions: SettingsDictionary = [
                    "SUPPORTED_PLATFORMS": .string((simulatorSDKs + (target.supports(.macOS) ? ["macosx"] : []))
                        .joined(separator: " ")),
                    "SDKROOT": .string(target.supports(.macOS) || simulatorSDKs.count > 1 ? "auto" : simulatorSDKs[0]),
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
