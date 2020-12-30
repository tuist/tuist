import Foundation
import TSCBasic

/// The metadata associated with a system framework or library (e.g. UIKit.framework, libc++.tbd)
public struct SystemFrameworkMetadata: Equatable {
    var name: String
    var path: AbsolutePath
    var status: SDKStatus
    var source: SDKSource

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
