import Foundation
import TSCBasic

/// The metadata associated with a precompiled library (.a / .dylib)
public struct LibraryMetadata: Equatable {
    public var path: AbsolutePath
    public var publicHeaders: AbsolutePath
    public var swiftModuleMap: AbsolutePath?
    public var architectures: [BinaryArchitecture]
    public var linking: BinaryLinking

    public init(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        architectures: [BinaryArchitecture],
        linking: BinaryLinking
    ) {
        self.path = path
        self.publicHeaders = publicHeaders
        self.swiftModuleMap = swiftModuleMap
        self.architectures = architectures
        self.linking = linking
    }
}
