import Foundation
import TSCBasic

public struct ProjectDescriptionHelpersModule: Equatable, Hashable {
    public let name: String
    public let path: AbsolutePath

    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}
