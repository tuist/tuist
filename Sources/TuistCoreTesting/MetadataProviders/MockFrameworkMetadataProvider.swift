import Foundation
import Path
import XcodeGraph
@testable import TuistCore

public final class MockFrameworkMetadataProvider: MockPrecompiledMetadataProvider, FrameworkMetadataProviding {
    public var loadMetadataStub: ((AbsolutePath) throws -> FrameworkMetadata)?
    public func loadMetadata(at path: AbsolutePath, status: LinkingStatus) throws -> FrameworkMetadata {
        if let loadMetadataStub {
            return try loadMetadataStub(path)
        } else {
            return FrameworkMetadata.test(path: path, status: status)
        }
    }

    public var dsymPathStub: ((AbsolutePath) throws -> AbsolutePath?)?
    public func dsymPath(frameworkPath: AbsolutePath) throws -> AbsolutePath? {
        try dsymPathStub?(frameworkPath) ?? nil
    }

    public var bcsymbolmapPathsStub: ((AbsolutePath) throws -> [AbsolutePath])?
    public func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath] {
        if let bcsymbolmapPathsStub {
            return try bcsymbolmapPathsStub(frameworkPath)
        } else {
            return []
        }
    }

    public var productStub: ((AbsolutePath) throws -> Product)?
    public func product(frameworkPath: AbsolutePath) throws -> Product {
        if let productStub {
            return try productStub(frameworkPath)
        } else {
            return .framework
        }
    }
}
