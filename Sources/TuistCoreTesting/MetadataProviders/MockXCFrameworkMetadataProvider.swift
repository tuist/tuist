import Foundation
import Path
import XcodeGraph
@testable import TuistCore

public final class MockXCFrameworkMetadataProvider: MockPrecompiledMetadataProvider, XCFrameworkMetadataProviding {
    public var loadMetadataStub: ((AbsolutePath) throws -> XCFrameworkMetadata)?
    public func loadMetadata(at path: AbsolutePath, status: LinkingStatus) throws -> XCFrameworkMetadata {
        if let loadMetadataStub {
            return try loadMetadataStub(path)
        } else {
            return XCFrameworkMetadata.test(
                path: path,
                primaryBinaryPath: path.appending(try RelativePath(validating: "ios-arm64/binary")),
                status: status
            )
        }
    }

    public var infoPlistStub: ((AbsolutePath) throws -> XCFrameworkInfoPlist)?
    public func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist {
        if let infoPlistStub {
            return try infoPlistStub(xcframeworkPath)
        } else {
            return XCFrameworkInfoPlist.test()
        }
    }

    public var binaryPathStub: ((AbsolutePath, [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath)?
    public func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath {
        if let binaryPathStub {
            return try binaryPathStub(xcframeworkPath, libraries)
        } else {
            return AbsolutePath.root
        }
    }
}
