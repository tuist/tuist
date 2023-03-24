import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public final class MockFrameworkMetadataProvider: MockPrecompiledMetadataProvider, FrameworkMetadataProviding {
    public var loadMetadataStub: ((AbsolutePath) throws -> FrameworkMetadata)?
    public func loadMetadata(at path: AbsolutePath) throws -> FrameworkMetadata {
        if let loadMetadataStub = loadMetadataStub {
            return try loadMetadataStub(path)
        } else {
            return FrameworkMetadata.test(path: path)
        }
    }

    public var dsymPathStub: ((AbsolutePath) throws -> AbsolutePath?)?
    public func dsymPath(frameworkPath: AbsolutePath) throws -> AbsolutePath? {
        try dsymPathStub?(frameworkPath) ?? nil
    }

    public var bcsymbolmapPathsStub: ((AbsolutePath) throws -> [AbsolutePath])?
    public func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath] {
        if let bcsymbolmapPathsStub = bcsymbolmapPathsStub {
            return try bcsymbolmapPathsStub(frameworkPath)
        } else {
            return []
        }
    }

    public var productStub: ((AbsolutePath) throws -> Product)?
    public func product(frameworkPath: AbsolutePath) throws -> Product {
        if let productStub = productStub {
            return try productStub(frameworkPath)
        } else {
            return .framework
        }
    }
}
