import Foundation

extension ProjectDescription.Project {
    public struct Configuration: Codable, Equatable {
        /// The project options.
        public let options: Project.Options
    }
}

extension ProjectDescription.Project.Configuration {
    public static func configuration(options: Project.Options) -> Self {
        .init(options: options)
    }
}
