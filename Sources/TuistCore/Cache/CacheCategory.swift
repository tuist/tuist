/// A cache category.
public enum CacheCategory: String, CaseIterable, RawRepresentable {
    /// The plugins cache.
    case plugins

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
        case .generatedAutomationProjects:
            return "Projects"
        case .projectDescriptionHelpers:
            return "ProjectDescriptionHelpers"
        case .manifests:
            return "Manifests"
        }
    }

    public enum App: String, CaseIterable {
        case binaries
        case selectiveTests

        public var directoryName: String {
            switch self {
            case .binaries:
                return "BinaryCache"
            case .selectiveTests:
                return "SelectiveTests"
            }
        }
    }
}
