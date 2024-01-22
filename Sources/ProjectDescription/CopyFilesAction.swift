import Foundation

/// A build phase action used to copy files.
///
/// Copy files actions, represented as target copy files build phases, are useful to associate project files
/// and products of other targets with the target and copies them to a specified destination, typically a
/// subfolder within a product. This action may be used multiple times per target.
public struct CopyFilesAction: Codable, Equatable {
    /// Name of the build phase when the project gets generated.
    public var name: String

    /// Destination to copy files to.
    public var destination: Destination

    /// Path to a folder inside the destination.
    public var subpath: String? = nil

    /// Relative paths to the files to be copied.
    public var files: [FileElement]

    /// Destination path.
    public enum Destination: String, Codable, Equatable {
        case absolutePath
        case productsDirectory
        case wrapper
        case executables
        case resources
        case javaResources
        case frameworks
        case sharedFrameworks
        case sharedSupport
        case plugins
        case other
    }
}
