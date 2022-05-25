import Foundation

extension TuistGraph.Project {
    public struct ProjectConfiguration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options
    }
}

extension TuistGraph.Project.ProjectConfiguration {
    public static func configuration(options: Project.Options) -> Self {
        .init(options: options)
    }
}
