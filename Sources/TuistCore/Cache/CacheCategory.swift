/// A cache category.
public enum CacheCategory: String, CaseIterable, RawRepresentable {
    /// The plugins cache.
    case plugins

    /// The build cache
    case builds

    /// The tests cache
    case tests

    /// The projects generated for automation tasks cache
    case generatedAutomationProjects

    /// The project description helpers cache
    case projectDescriptionHelpers

    /// The manifests cache
    case manifests

    public var directoryName: String {
        switch self {
        case .plugins:
            return "Plugins"
        case .builds:
            return "BuildCache"
        case .tests:
            return "incremental-tests"
        case .generatedAutomationProjects:
            return "Projects"
        case .projectDescriptionHelpers:
            return "ProjectDescriptionHelpers"
        case .manifests:
            return "Manifests"
        }
    }
}
