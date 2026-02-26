import Foundation
import Path

/// The metadata associated with a system framework or library (e.g. UIKit.framework, libc++.tbd)
public struct SystemFrameworkMetadata: Equatable {
    public var name: String
    public var path: AbsolutePath
    public var status: LinkingStatus
    public var source: SDKSource

    public init(
        name: String,
        path: AbsolutePath,
        status: LinkingStatus,
        source: SDKSource
    ) {
        self.name = name
        self.path = path
        self.status = status
        self.source = source
    }
}
