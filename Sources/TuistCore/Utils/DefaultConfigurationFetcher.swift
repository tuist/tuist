import Foundation
import Mockable
import TuistSupport
import XcodeGraph

@Mockable
public protocol DefaultConfigurationFetching {
    func fetch(
        configuration: String?,
        config: TuistCore.Config,
        graph: XcodeGraph.Graph
    ) throws -> String
}

enum DefaultConfigurationFetcherError: FatalError, Equatable {
    case debugBuildConfigurationNotFound
    case configurationNotFound(String, available: [String])
    case defaultConfigurationNotFound(String, available: [String])

    var type: ErrorType {
        switch self {
        case .debugBuildConfigurationNotFound, .configurationNotFound, .defaultConfigurationNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .debugBuildConfigurationNotFound:
            return "We couldn't find a build configuration of variant 'debug' for caching. Make sure one exists in the project."
        case let .configurationNotFound(configuration, available):
            return "We couldn't find the configuration \(configuration) in the project. The configurations available are: \(available.joined(separator: ", "))"
        case let .defaultConfigurationNotFound(configuration, available):
            return "We couldn't find the default configuration \(configuration) specified in your Config.swift in the project. The configurations available are: \(available.joined(separator: ", "))"
        }
    }
}

public struct DefaultConfigurationFetcher: DefaultConfigurationFetching {
    public init() {}

    public func fetch(
        configuration: String?,
        config: TuistCore.Config,
        graph: XcodeGraph.Graph
    ) throws -> String {
        let allProjectConfigurations = Set(graph.projects.values.map(\.settings).flatMap(\.configurations.keys)).sorted()

        if let configuration {
            if allProjectConfigurations.first(where: { $0.name == configuration }) != nil {
                return configuration
            } else {
                throw DefaultConfigurationFetcherError.configurationNotFound(
                    configuration,
                    available: allProjectConfigurations.map(\.name)
                )
            }
        }

        if let defaultConfiguration = config.generationOptions.defaultConfiguration {
            if allProjectConfigurations.first(where: { $0.name == defaultConfiguration }) != nil {
                return defaultConfiguration
            } else {
                throw DefaultConfigurationFetcherError.defaultConfigurationNotFound(
                    defaultConfiguration,
                    available: allProjectConfigurations.map(\.name)
                )
            }
        }

        guard let debugConfigurationName = graph.projects.values.map(\.settings).flatMap(\.configurations.keys).sorted()
            .first(where: {
                $0.variant == .debug
            })?.name
        else {
            throw DefaultConfigurationFetcherError.debugBuildConfigurationNotFound
        }

        return debugConfigurationName
    }
}
