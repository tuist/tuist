import Foundation
import Path

public enum Manifest: CaseIterable {
    case project
    case workspace
    case config
    case template
    case plugin
    case package
    case packageSettings

    /// - Parameters:
    ///     - path: Path to the folder that contains the manifest
    /// - Returns: File name of the `Manifest`
    public func fileName(_ path: AbsolutePath) -> String {
        switch self {
        case .project:
            return "Project.swift"
        case .workspace:
            return "Workspace.swift"
        case .config:
            return "Config.swift"
        case .template:
            return "\(path.basenameWithoutExt).swift"
        case .plugin:
            return "Plugin.swift"
        case .package, .packageSettings:
            return "Package.swift"
        }
    }

    /// This is needed to allow migrating from Tuist/Config.swift to Tuist.swift without introducing breaking changes.
    /// Upstream logic that needs to get the path can use this function to fall back to another path.
    /// - Parameter path: Path to resolve from.
    /// - Returns: An alternative manifest fil ename.
    public func alternativeFileName(_: AbsolutePath) -> String? {
        switch self {
        case .project:
            return nil
        case .workspace:
            return nil
        case .config:
            return "Tuist.swift"
        case .template:
            return nil
        case .plugin:
            return nil
        case .package, .packageSettings:
            return nil
        }
    }
}
