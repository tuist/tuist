/// A cache category.
public enum CacheCategory: CaseIterable {
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
}
