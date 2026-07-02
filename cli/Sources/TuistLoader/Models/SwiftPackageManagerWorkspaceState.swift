/// The Swift Package Manager workspace information.
/// It decodes data encoded from WorkspaceState.swift: https://github.com/apple/swift-package-manager/blob/ce50cb0de101c2d9a5742aaf70efc7c21e8f249b/Sources/Workspace/WorkspaceState.swift
/// In particular, we are interested in the ManagedDependency.swift: https://github.com/apple/swift-package-manager/blob/ce50cb0de101c2d9a5742aaf70efc7c21e8f249b/Sources/Workspace/ManagedDependency.swift
/// Fields not needed by tuist are commented out and not decoded at all.
public struct SwiftPackageManagerWorkspaceState: Decodable, Equatable {
    /// The products declared in the manifest.
    public let object: Object

    public struct Object: Decodable, Equatable {
        /// The list of SPM dependencies
        public let dependencies: [Dependency]

        /// The list of SPM artifacts
        public let artifacts: [Artifact]

        /// The list of SPM prebuilts
        public let prebuilts: [Prebuilt]

        private enum CodingKeys: String, CodingKey {
            case dependencies
            case artifacts
            case prebuilts
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dependencies = try container.decode([Dependency].self, forKey: .dependencies)
            artifacts = try container.decode([Artifact].self, forKey: .artifacts)
            prebuilts = try container.decodeIfPresent([Prebuilt].self, forKey: .prebuilts) ?? []
        }
    }

    public struct Dependency: Decodable, Equatable {
        public struct State: Decodable, Equatable {
            public struct CheckoutState: Decodable, Equatable {
                public let revision: String?
            }

            /// The revision a package has been resolved to.
            public let checkoutState: CheckoutState?

            /// The version a package has been resolved to.
            public let version: String?
        }

        /// The package reference of the dependency
        public let packageRef: PackageRef

        /// The path of the remote dependency, relative to the checkouts folder
        public let subpath: String

        /// The state of the dependency.
        public let state: State?
    }

    public struct Artifact: Decodable, Equatable {
        /// The package reference of the artifact
        public let packageRef: PackageRef

        /// The absolute path to the artifact (in local file system)
        public let path: String

        /// Name of the target to which this artifact belongs
        public let targetName: String
    }

    public struct Prebuilt: Decodable, Equatable {
        /// Identity of the package the prebuilt belongs to.
        public let identity: String

        /// Version of the package the prebuilt was built from.
        public let version: String

        /// Name of the prebuilt library.
        public let libraryName: String

        /// Absolute path to the extracted prebuilt artifacts.
        public let path: String

        /// Absolute path to the source checkout associated with the prebuilt.
        public let checkoutPath: String?

        /// Products represented by this prebuilt library.
        public let products: [String]

        /// Include paths relative to the checkout path.
        public let includePath: [String]?

        /// C modules with include directories in the prebuilt artifact.
        public let cModules: [String]
    }

    public struct PackageRef: Decodable, Equatable {
        /// Identity of the dependency
        public let identity: String
        /// The name of the dependency
        public let name: String
        /// The king of the dependency (either local or remote)
        public let kind: String
        /// The path of the local dependency, no longer available since Swift 5.5
        public let path: String?
        /// The location of the dependency
        public let location: String?
    }
}
