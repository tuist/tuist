public enum TuistProject: Codable, Equatable, Sendable {
    /// Creates a configuration for a Tuist project.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    ///   - installOptions: List of options to use when running `tuist install`.
    ///   - cacheOptions: Options to configure the caching functionality.
    case tuist(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        plugins: [PluginLocation] = [],
        generationOptions: Tuist.GenerationOptions = .options(),
        installOptions: Tuist.InstallOptions = .options(),
        cacheOptions: Tuist.CacheOptions = .options()
    )
    case xcode(TuistXcodeProjectOptions = TuistXcodeProjectOptions.options())

    @available(
        *,
        deprecated,
        message: "`swiftVersion` is unused and no longer affects generation. Remove it from your configuration."
    )
    public static func tuist(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        swiftVersion _: Version?,
        plugins: [PluginLocation] = [],
        generationOptions: Tuist.GenerationOptions = .options(),
        installOptions: Tuist.InstallOptions = .options(),
        cacheOptions: Tuist.CacheOptions = .options()
    ) -> TuistProject {
        .tuist(
            compatibleXcodeVersions: compatibleXcodeVersions,
            plugins: plugins,
            generationOptions: generationOptions,
            installOptions: installOptions,
            cacheOptions: cacheOptions
        )
    }
}
