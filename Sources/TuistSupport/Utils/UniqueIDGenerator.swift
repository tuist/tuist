import Foundation
import Mockable

@Mockable
public protocol UniqueIDGenerating {
    func uniqueID() -> String
}

public struct UniqueIDGenerator: UniqueIDGenerating {
    public init() {}

    public func uniqueID() -> String {
        UUID().uuidString
    }
}
