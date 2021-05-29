import TuistCore
import TuistGraph
import XcodeProj

extension CopyFilesAction.Destination {
    var toXcodeprojSubFolder: PBXCopyFilesBuildPhase.SubFolder {
        switch self {
        case .absolutePath:
            return .absolutePath
        case .productsDirectory:
            return .productsDirectory
        case .wrapper:
            return .wrapper
        case .executables:
            return .executables
        case .resources:
            return .resources
        case .javaResources:
            return .javaResources
        case .frameworks:
            return .frameworks
        case .sharedFrameworks:
            return .sharedFrameworks
        case .sharedSupport:
            return .sharedSupport
        case .plugins:
            return .plugins
        case .other:
            return .other
        }
    }
}
