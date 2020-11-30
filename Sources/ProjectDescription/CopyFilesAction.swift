import Foundation

public struct CopyFilesAction: Equatable, Codable {
    public var name: String
    public var destination: Destination
    public var subpath: String
    public var files: [FileElement]

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

    public init(name: String,
                destination: Destination,
                subpath: String,
                files: [FileElement])
    {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.files = files
    }
}
