import XcodeGraph

public enum TuistProject: Equatable, Hashable {
    /// Creates a configuration for a Tuist project.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    ///   - installOptions: List of options to use when running `tuist install`.
    case generated(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: Tuist.GenerationOptions,
        installOptions: Tuist.InstallOptions
    )
    case xcode

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .generated(compatibleXcodeVersions, swiftVersion, _, generationOptions, _):
            hasher.combine("type-generated")
            hasher.combine(generationOptions)
            hasher.combine(swiftVersion)
            hasher.combine(compatibleXcodeVersions)
        case .xcode:
            hasher.combine("type-xcode")
        }
    }

    public static func defaultGeneratedProject() -> Self {
        return .generated(
            compatibleXcodeVersions: .all,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                staticSideEffectsWarningTargets: .all
            ),
            installOptions: .init(passthroughSwiftPackageManagerArguments: [])
        )
    }
}
