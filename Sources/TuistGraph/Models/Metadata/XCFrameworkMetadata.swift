import Foundation
import TSCBasic

/// The metadata associated with a precompiled xcframework
public struct XCFrameworkMetadata: Equatable {
    public var path: AbsolutePath
    public var infoPlist: XCFrameworkInfoPlist
    public var primaryBinaryPath: AbsolutePath
    public var linking: BinaryLinking
    public var mergeable: Bool

    public init(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        linking: BinaryLinking,
        mergeable: Bool
    ) {
        self.path = path
        self.infoPlist = infoPlist
        self.primaryBinaryPath = primaryBinaryPath
        self.linking = linking
        self.mergeable = mergeable
    }
}
