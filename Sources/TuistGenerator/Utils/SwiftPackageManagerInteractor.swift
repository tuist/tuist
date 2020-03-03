import Basic
import Foundation
import TuistCore
import TuistSupport

public protocol SwiftPackageManagerInteracting {
    func install(graph: Graphing, workspaceName: String) throws
}

public class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func install(graph: Graphing, workspaceName: String) throws {
        try generatePackageDependencyManager(at: graph.entryPath,
                                             workspaceName: workspaceName,
                                             graph: graph)
    }

    private func generatePackageDependencyManager(
        at path: AbsolutePath,
        workspaceName: String,
        graph: Graphing
    ) throws {
        let packages = graph.packages
        guard !packages.remotePackages.isEmpty else {
            return
        }

        let rootPackageResolvedPath = path.appending(component: ".package.resolved")
        let workspacePackageResolvedFolderPath = path.appending(RelativePath("\(workspaceName)/xcshareddata/swiftpm"))
        let workspacePackageResolvedPath = workspacePackageResolvedFolderPath.appending(component: "Package.resolved")

        if fileHandler.exists(rootPackageResolvedPath) {
            try fileHandler.createFolder(workspacePackageResolvedFolderPath)
            if fileHandler.exists(workspacePackageResolvedPath) {
                try fileHandler.delete(workspacePackageResolvedPath)
            }
            try fileHandler.copy(from: rootPackageResolvedPath, to: workspacePackageResolvedPath)
        }

        let workspacePath = path.appending(component: workspaceName)
        // -list parameter is a workaround to resolve package dependencies for given workspace without specifying scheme
        try System.shared.runAndPrint(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])

        if fileHandler.exists(rootPackageResolvedPath) {
            try fileHandler.delete(rootPackageResolvedPath)
        }

        try fileHandler.linkFile(atPath: workspacePackageResolvedPath, toPath: rootPackageResolvedPath)
    }
}

private extension Array where Element == PackageNode {
    var remotePackages: [PackageNode] {
        compactMap { node in
            switch node.package {
            case .remote:
                return node
            default:
                return nil
            }
        }
    }
}
