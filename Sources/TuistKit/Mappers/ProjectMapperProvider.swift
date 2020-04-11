import Foundation
import TuistCache
import TuistCore
import TuistGenerator

/// It defines an interface for providing the mappers to be used for a specific configuration.
protocol ProjectMapperProviding {
    /// Returns a list of mappers to be used for a specific configuration.
    /// - Parameter config: Project's configuration.
    func mapper(config: Config) -> ProjectMapping
}

final class ProjectMapperProvider: ProjectMapperProviding {
    init() {}

    func mapper(config: Config) -> ProjectMapping {
        SequentialProjectMapper(mappers: mappers(config: config))
    }

    func mappers(config _: Config) -> [ProjectMapping] {
        var mappers: [ProjectMapping] = []

        // Derived
        mappers.append(DeleteDerivedDirectoryProjectMapper())
        mappers.append(GenerateInfoPlistProjectMapper())

        return mappers
    }
}
