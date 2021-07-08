/// The Swift Package Manager workspace information.
/// It decodes data encoded from WorkspaceState.swift: https://github.com/apple/swift-package-manager/blob/ce50cb0de101c2d9a5742aaf70efc7c21e8f249b/Sources/Workspace/WorkspaceState.swift
/// In particular, we are interested in the ManagedDependency.swift: https://github.com/apple/swift-package-manager/blob/ce50cb0de101c2d9a5742aaf70efc7c21e8f249b/Sources/Workspace/ManagedDependency.swift
/// Fields not needed by tuist are commented out and not decoded at all.
struct SwiftPackageManagerWorkspaceState: Decodable, Equatable {
    /// The products declared in the manifest.
    let object: Object

    struct Object: Decodable, Equatable {
        /// The list of SPM dependencies
        let dependencies: [Dependency]
    }

    struct Dependency: Decodable, Equatable {
        /// The package reference of the dependency
        let packageRef: PackageRef

        /// The path of the remote dependency, relative to the checkouts folder
        let subpath: String
    }

    struct PackageRef: Decodable, Equatable {
        /// The name of the dependency
        let name: String
        /// The king of the dependency (either local or remote)
        let kind: String
        /// The path of the local dependency
        let path: String
    }
}
