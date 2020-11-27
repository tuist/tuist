import Foundation
import TSCBasic

public struct CopyFilesAction: Equatable {
    public var name: String
    public var destination: Destination
    public var subpath: String
    public var files: [FileElement]

    public enum Destination: UInt, Equatable {
        case absolutePath = 0
        case productsDirectory = 16
        case wrapper = 1
        case executables = 6
        case resources = 7
        case javaResources = 15
        case frameworks = 10
        case sharedFrameworks = 11
        case sharedSupport = 12
        case plugins = 13
        case other
    }

    public init(
            name: String,
            destination: Destination,
            subpath: String,
            files: [FileElement]
    ) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.files = files
    }
}
