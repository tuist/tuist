import Basic
import Foundation
@testable import TuistCore

public final class MockXCFrameworkMetadataProvider: MockPrecompiledMetadataProvider, XCFrameworkMetadataProviding {
    public var infoPlistStub: ((AbsolutePath) throws -> XCFrameworkInfoPlist)?
    public func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist {
        if let infoPlistStub = infoPlistStub {
            return try infoPlistStub(xcframeworkPath)
        } else {
            return XCFrameworkInfoPlist.test()
        }
    }

    public var binaryPathStub: ((AbsolutePath, [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath)?
    public func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath {
        if let binaryPathStub = binaryPathStub {
            return try binaryPathStub(xcframeworkPath, libraries)
        } else {
            return AbsolutePath.root
        }
    }
}
