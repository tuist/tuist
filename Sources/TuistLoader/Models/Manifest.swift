import Foundation

public enum Manifest: CaseIterable {
    case project
    case workspace
    case tuistConfig
    case setup
    case galaxy

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
        case .galaxy:
            return "Galaxy.swift"
        }
    }
}
