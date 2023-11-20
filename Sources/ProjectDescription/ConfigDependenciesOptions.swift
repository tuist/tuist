extension Config {
    /// Options for external dependencies.
    public struct DependenciesOptions: Codable, Equatable {
        /// The path of the `Package.swift` file. If not specified, it's `Tuist/Package.swift`.
        public let packagePath: Path

        /// List of platforms for which you want to install dependencies.
        public let platforms: Set<Platform>

        /// The custom `Product` type to be used for SwiftPackageManager targets.
        public let productTypes: [String: Product]

        /// The base settings to be used for targets generated from SwiftPackageManager.
        public let baseSettings: Settings

        /// Additional settings to be added to targets generated from SwiftPackageManager.
        public let targetSettings: [String: SettingsDictionary]

        /// Custom project configurations to be used for projects generated from SwiftPackageManager.
        public let projectOptions: [String: ProjectDescription.Project.Options]

        public static func options(
            packagePath: Path = .relativeToRoot("Tuist/Package.swift"),
            platforms: Set<Platform> = Set(Platform.allCases),
            productTypes: [String: Product] = [:],
            baseSettings: Settings = .settings(),
            targetSettings: [String: SettingsDictionary] = [:],
            projectOptions: [String: ProjectDescription.Project.Options] = [:]
        ) -> Self {
            self.init(
                packagePath: packagePath,
                platforms: platforms,
                productTypes: productTypes,
                baseSettings: baseSettings,
                targetSettings: targetSettings,
                projectOptions: projectOptions
            )
        }
    }
}
