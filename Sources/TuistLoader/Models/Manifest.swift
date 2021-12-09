import Foundation
import TSCBasic

public enum Manifest: CaseIterable {
    case project
    case workspace
    case config
    case template
    case dependencies
    case plugin

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
        case .dependencies:
            return "Dependencies.swift"
        case .plugin:
            return "Plugin.swift"
        }
    }
}
