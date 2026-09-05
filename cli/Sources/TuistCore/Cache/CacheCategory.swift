import Foundation

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

    /// The edit projects cache
    case editProjects

    /// The Tuist Runs cache
    case runs

    /// The Tuist Binaries cache
    case binaries

    /// The Tuist Selective Tests cache
    case selectiveTests

    /// Per-project generation metadata, used to link local Xcode builds back to the graph
    /// uploaded by the last `tuist generate`.
    case generationMetadata

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
        case .editProjects:
            return "EditProjects"
        case .runs:
            return "Runs"
        case .binaries:
            return "Binaries"
        case .selectiveTests:
            return "SelectiveTests"
        case .generationMetadata:
            return "GenerationMetadata"
        }
    }

    /// Which share of the CLI's byte budget bounds a category's growth.
    ///
    /// The cache directory can be a runner's per-account cache volume, an image with a fixed
    /// capacity. The host stages one budget for the whole of it and `CacheBudget` divides that
    /// between the two shares below, so the categories cannot together exceed what the volume was
    /// sized for. Every category has to name the share that bounds it, so that adding one cannot
    /// silently add an unbounded tenant.
    public enum Budget: Equatable, Sendable {
        /// Bounded by `CacheBudget.moduleCache`, enforced where the artifacts are stored and
        /// fetched.
        case binaries

        /// Bounded by `CacheBudget.supportCaches`, enforced by `SupportCachePruner`. Entries unused
        /// for `maxAge` are dropped before the budget is considered, so what the budget arbitrates
        /// is only what is still in use.
        case support(maxAge: TimeInterval)
    }

    private static let day: TimeInterval = 60 * 60 * 24

    public var budget: Budget {
        switch self {
        case .binaries:
            return .binaries
        case .runs:
            // A result bundle is only alive between the run finishing and its analytics upload,
            // which deletes it. A survivor is a run whose process died, and nothing will ever
            // upload it.
            return .support(maxAge: Self.day)
        case .manifests, .projectDescriptionHelpers, .editProjects, .generatedAutomationProjects:
            // Recomputed from the sources they were derived from: a manifest reload, one swiftc
            // invocation, a project generation.
            return .support(maxAge: 7 * Self.day)
        case .plugins, .selectiveTests, .generationMetadata:
            // Refetched over the network, or read long after the run that wrote them, so these are
            // kept for as long as they plausibly stay relevant.
            return .support(maxAge: 30 * Self.day)
        }
    }

    /// The categories the shared support-cache budget bounds, in the order they are evicted:
    /// what costs the least to lose goes first.
    public static let supportCaches: [CacheCategory] = [
        .runs,
        .manifests,
        .editProjects,
        .generatedAutomationProjects,
        .projectDescriptionHelpers,
        .selectiveTests,
        .generationMetadata,
        .plugins,
    ]
}

public enum RemoteCacheCategory: Codable {
    case binaries
    case selectiveTests
}
