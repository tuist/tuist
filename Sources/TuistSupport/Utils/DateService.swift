import Foundation
import Mockable

@Mockable
public protocol DateServicing: Sendable {
    func now() -> Date
}

public struct DateService: DateServicing {
    public init() {}

    public func now() -> Date {
        Date()
    }
}
