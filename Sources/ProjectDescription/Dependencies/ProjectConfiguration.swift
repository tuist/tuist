import Foundation

extension ProjectDescription.Project {
    public struct ProjectConfiguration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options

        /// The resource synthesizers for the project to generate accessors for resources.
        public let resourceSynthesizers: [ProjectDescription.ResourceSynthesizer]
    }
}

extension ProjectDescription.Project.ProjectConfiguration {
    public static func configuration(
        options: Project.Options,
        resourceSynthesizers: [ProjectDescription.ResourceSynthesizer]
    ) -> Self {
        .init(options: options, resourceSynthesizers: resourceSynthesizers)
    }
}
