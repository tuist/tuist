import Foundation

extension TuistGraph.Project {
    public struct Configuration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options
    }
}

extension TuistGraph.Project.Configuration {
    public static func configuration(options: Project.Options) -> Self {
        .init(options: options)
    }
}
