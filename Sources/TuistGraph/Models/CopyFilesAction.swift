import Foundation
import TSCBasic

public struct CopyFilesAction: Equatable, Codable {
    /// Name of the build phase when the project gets generated.
    public var name: String

    /// Destination to copy files to.
    public var destination: Destination

    /// Path to a folder inside the destination.
    public var subpath: String?

    /// Relative paths to the files to be copied.
    public var files: [FileElement]

    /// Destination path.
    public enum Destination: String, Equatable, Codable {
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

    public init(
        name: String,
        destination: Destination,
        subpath: String? = nil,
        files: [FileElement]
    ) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.files = files
    }
}
