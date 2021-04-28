import Foundation
import TSCBasic

public struct TestPlan: Equatable, Codable {
    public let path: AbsolutePath
    public let isDefault: Bool

    public init(path: AbsolutePath, isDefault: Bool) {
        self.path = path
        self.isDefault = isDefault
    }
}
