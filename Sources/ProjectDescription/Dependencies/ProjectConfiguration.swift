import Foundation

extension ProjectDescription.Project {
    public struct ProjectConfiguration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options
    }
}

extension ProjectDescription.Project.ProjectConfiguration {
    public static func configuration(options: Project.Options) -> Self {
        .init(options: options)
    }
}
