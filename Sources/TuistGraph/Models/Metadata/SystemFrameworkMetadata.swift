import Foundation
import TSCBasic

/// The metadata associated with a system framework or library (e.g. UIKit.framework, libc++.tbd)
public struct SystemFrameworkMetadata: Equatable {
    public var name: String
    public var path: AbsolutePath
    public var status: SDKStatus
    public var source: SDKSource

    public init(
        name: String,
        path: AbsolutePath,
        status: SDKStatus,
        source: SDKSource
    ) {
        self.name = name
        self.path = path
        self.status = status
        self.source = source
    }
}
