import Foundation

/// Represents a manifest file type.
public enum ManifestFile: CaseIterable {
    /// Project.swift
    case project

    /// Workspace.swift
    case workspace

    /// TuistConfig.swift
    case tuistConfig

    /// Setup.swift
    case setup

    /// Manifest file name.
    public var fileName: String {
        switch self {
        case .project:
            return "Project.swift"
        case .workspace:
            return "Workspace.swift"
        case .tuistConfig:
            return "TuistConfig.swift"
        case .setup:
            return "Setup.swift"
        }
    }
}
