import Foundation
import TSCBasic
@testable import TuistCore

public final class MockFrameworkMetadataProvider: MockPrecompiledMetadataProvider, FrameworkMetadataProviding {
    public var dsymPathStub: ((AbsolutePath) -> AbsolutePath?)?
    public func dsymPath(frameworkPath: AbsolutePath) -> AbsolutePath? {
        dsymPathStub?(frameworkPath) ?? nil
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
