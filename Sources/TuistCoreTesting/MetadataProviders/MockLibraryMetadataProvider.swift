import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public final class MockLibraryMetadataProvider: MockPrecompiledMetadataProvider, LibraryMetadataProviding {
    public var loadMetadataStub: ((AbsolutePath, AbsolutePath, AbsolutePath?) throws -> LibraryMetadata)?
    public func loadMetadata(
        at path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?
    ) throws -> LibraryMetadata {
        if let stub = loadMetadataStub {
            return try stub(path, publicHeaders, swiftModuleMap)
        } else {
            return LibraryMetadata.test(
                path: path,
                publicHeaders: publicHeaders,
                swiftModuleMap: swiftModuleMap
            )
        }
    }
}
