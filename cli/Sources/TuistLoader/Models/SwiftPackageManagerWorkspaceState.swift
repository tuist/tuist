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

        /// The list of SPM prebuilts
        let prebuilts: [Prebuilt]

        private enum CodingKeys: String, CodingKey {
            case dependencies
            case artifacts
            case prebuilts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dependencies = try container.decode([Dependency].self, forKey: .dependencies)
            artifacts = try container.decode([Artifact].self, forKey: .artifacts)
            prebuilts = try container.decodeIfPresent([Prebuilt].self, forKey: .prebuilts) ?? []
        }
    }

    struct Dependency: Decodable, Equatable {
        struct State: Decodable, Equatable {
            struct CheckoutState: Decodable, Equatable {
                let revision: String?
            }

            /// The revision a package has been resolved to.
            let checkoutState: CheckoutState?

            /// The version a package has been resolved to.
            let version: String?
        }

        /// The package reference of the dependency
        let packageRef: PackageRef

        /// The path of the remote dependency, relative to the checkouts folder
        let subpath: String

        /// The state of the dependency.
        let state: State?
    }

    struct Artifact: Decodable, Equatable {
        /// The package reference of the artifact
        let packageRef: PackageRef

        /// The absolute path to the artifact (in local file system)
        let path: String

        /// Name of the target to which this artifact belongs
        let targetName: String
    }

    struct Prebuilt: Decodable, Equatable {
        /// Identity of the package the prebuilt belongs to.
        let identity: String

        /// Version of the package the prebuilt was built from.
        let version: String

        /// Name of the prebuilt library.
        let libraryName: String

        /// Absolute path to the extracted prebuilt artifacts.
        let path: String

        /// Absolute path to the source checkout associated with the prebuilt.
        let checkoutPath: String?

        /// Products represented by this prebuilt library.
        let products: [String]

        /// Include paths relative to the checkout path.
        let includePath: [String]?

        /// C modules with include directories in the prebuilt artifact.
        let cModules: [String]
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
