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

        /// The list of SPM artifacts
        let artifacts: [Artifact]
    }

    struct Dependency: Decodable, Equatable {
        /// The package reference of the dependency
        let packageRef: PackageRef

        /// The path of the remote dependency, relative to the checkouts folder
        let subpath: String
    }

    struct Artifact: Decodable, Equatable {
        /// The package reference of the artifact
        let packageRef: PackageRef

        /// The absolute path to the artifact (in local file system)
        let path: String

        /// Name of the target to which this artifact belongs
        let targetName: String
    }

    struct PackageRef: Decodable, Equatable {
        /// Identity of the dependency
        let identity: String
        /// The name of the dependency
        let name: String
        /// The king of the dependency (either local or remote)
        let kind: String
        /// The path of the local dependency, no longer available since Swift 5.5
        let path: String?
        /// The location of the dependency
        let location: String?
    }
}
