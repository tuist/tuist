import Foundation
import TSCBasic
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

public extension FrameworkMetadata {
    static func test(
        path: AbsolutePath = "/Frameworks/TestFramework.xframework",
        binaryPath: AbsolutePath = "/Frameworks/TestFramework.xframework/TestFramework",
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        isCarthage: Bool = false
    ) -> FrameworkMetadata {
        FrameworkMetadata(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            isCarthage: isCarthage
        )
    }
}
