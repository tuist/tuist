import Foundation
import TSCBasic

public enum Manifest: CaseIterable {
    case project
    case workspace
    case config
    case setup
    case template
    case galaxy

    /// This was introduced to rename a file name without breaking existing projects.
    public var deprecatedFileName: String? {
        switch self {
        case .config:
            return "TuistConfig.swift"
        case .template:
            return "Template.swift"
        default:
            return nil
        }
    }

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
        case .setup:
            return "Setup.swift"
        case .template:
            return "\(path.basenameWithoutExt).swift"
        case .galaxy:
            return "Galaxy.swift"
        }
    }
}
