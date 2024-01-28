/// A cache category.
public enum CacheCategory: String, CaseIterable, RawRepresentable {
    /// The plugins cache.
    case plugins

    /// The binary cache
    case binaries

    /// The selective tests cache
    case selectiveTests

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
        case .binaries:
            return "BinaryCache"
        case .selectiveTests:
            return "SelectiveTests"
        case .generatedAutomationProjects:
            return "Projects"
        case .projectDescriptionHelpers:
            return "ProjectDescriptionHelpers"
        case .manifests:
            return "Manifests"
        }
    }
}
