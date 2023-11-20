import TSCBasic

extension Config {
    public struct DependenciesOptions: Codable, Hashable {
        public let packagePath: AbsolutePath
        public let productTypes: [String: Product]
        public let baseSettings: Settings
        public let targetSettings: [String: SettingsDictionary]
        public let platforms: Set<Platform>

        public init(
            packagePath: AbsolutePath,
            platforms: Set<Platform>,
            productTypes: [String: Product],
            baseSettings: Settings,
            targetSettings: [String: SettingsDictionary]
        ) {
            self.packagePath = packagePath
            self.platforms = platforms
            self.productTypes = productTypes
            self.baseSettings = baseSettings
            self.targetSettings = targetSettings
        }
    }
}
