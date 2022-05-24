import Foundation

extension TuistGraph.Project {
    public struct ProjectConfiguration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options

        /// The resource synthesizers for the project to generate accessors for resources.
        public let resourceSynthesizers: [TuistGraph.ResourceSynthesizer]
    }
}

extension TuistGraph.Project.ProjectConfiguration {
    public static func configuration(
        options: Project.Options,
        resourceSynthesizers: [TuistGraph.ResourceSynthesizer]
    ) -> Self {
        .init(options: options, resourceSynthesizers: resourceSynthesizers)
    }
}
