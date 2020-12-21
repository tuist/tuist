import Foundation
import TSCBasic
@testable import TuistCore

public final class MockLibraryMetadataProvider: MockPrecompiledMetadataProvider, LibraryMetadataProviding {
    public var loadMetadataStub: ((AbsolutePath, AbsolutePath, AbsolutePath?) throws -> LibraryMetadata)?
    public func loadMetadata(at path: AbsolutePath,
                             publicHeaders: AbsolutePath,
                             swiftModuleMap: AbsolutePath?) throws -> LibraryMetadata
    {
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

public extension LibraryMetadata {
    static func test(
        path: AbsolutePath = "/Libraries/libTest/libTest.a",
        publicHeaders: AbsolutePath = "/Libraries/libTest/include",
        swiftModuleMap: AbsolutePath? = "/Libraries/libTest/libTest.swiftmodule",
        architectures: [BinaryArchitecture] = [.arm64],
        linking: BinaryLinking = .static
    ) -> LibraryMetadata {
        LibraryMetadata(
            path: path,
            publicHeaders: publicHeaders,
            swiftModuleMap: swiftModuleMap,
            architectures: architectures,
            linking: linking
        )
    }
}
